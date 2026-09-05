"""定时备份调度器（APScheduler）—— 每分钟检查一次，执行到期的备份任务。"""

import json
import logging
from datetime import datetime
from typing import Any

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.models.backup import ScheduledBackup
from app.services import backup_service

logger = logging.getLogger("app.backup_scheduler")

_scheduler: AsyncIOScheduler | None = None


def _execute_backup(schedule_id: int, db: Session) -> str:
    """执行单个定时备份任务，返回状态 'success' 或 'failed'。"""
    try:
        sched = db.get(ScheduledBackup, schedule_id)
        if not sched or not sched.enabled:
            return "skipped"

        # 确定要导出的表
        if sched.table_selection == "selected" and sched.selected_tables:
            tables = json.loads(sched.selected_tables)
        else:
            tables = None  # 全部表

        if sched.export_format == "sql":
            data, _ = backup_service.export_sql_mysqldump(tables)
        else:
            data, _ = backup_service.export_tables_json(
                db, tables, sched.compress
            )

        # 写入备份文件
        ext = ".sql" if sched.export_format == "sql" else ".zip" if sched.compress else ".json"
        filename = backup_service._backup_filename(sched.name, ext)
        filepath = backup_service.BACKUP_DIR / filename
        filepath.write_bytes(data)

        logger.info("定时备份 '%s' 完成：%s", sched.name, filename)
        return "success"
    except Exception as exc:
        logger.exception("定时备份 '%s' 失败：%s", sched.name, exc)
        return "failed"


def _scan_job() -> None:
    """每分钟扫描，执行所有到期且启用的定时备份任务。"""
    db = SessionLocal()
    try:
        now = datetime.now()
        schedules = db.scalars(
            select(ScheduledBackup).where(ScheduledBackup.enabled == True)  # noqa: E712
        ).all()

        for s in schedules:
            if not _cron_matches(s.cron_expression, now):
                continue

            status = _execute_backup(s.id, db)
            db.execute(
                update(ScheduledBackup)
                .where(ScheduledBackup.id == s.id)
                .values(last_run_at=now, last_status=status)
            )
            db.commit()
    except Exception as exc:
        logger.exception("定时备份扫描异常：%s", exc)
    finally:
        db.close()


def _cron_matches(expr: str, dt: datetime) -> bool:
    """简易 cron 匹配（支持标准5字段：*、数字、逗号列表、步进 */N）。"""
    parts = expr.strip().split()
    if len(parts) != 5:
        return False
    minute, hour, day, month, dow = parts
    return (
        _field_match(minute, dt.minute)
        and _field_match(hour, dt.hour)
        and _field_match(day, dt.day)
        and _field_match(month, dt.month)
        and _dow_match(dow, dt.weekday())
    )


def _field_match(pattern: str, value: int) -> bool:
    """匹配单个 cron 字段（支持 *、数字、逗号列表、步进 */N）。"""
    if pattern == "*":
        return True

    # 步进：*/N  → 每隔 N
    if pattern.startswith("*/"):
        step = pattern[2:]
        if step.isdigit():
            return value % int(step) == 0
        return False

    # 逗号列表：1,3,5
    if "," in pattern:
        return any(_field_match(p.strip(), value) for p in pattern.split(","))

    # 范围：1-5
    if "-" in pattern:
        parts = pattern.split("-")
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            return int(parts[0]) <= value <= int(parts[1])
        return False

    return int(pattern) == value if pattern.isdigit() else False


def _dow_match(pattern: str, weekday: int) -> bool:
    """匹配星期几（0=Monday 在 cron 中 0=Sunday，需转换）。"""
    if pattern == "*":
        return True
    # cron: 0=Sunday, 6=Saturday; Python: 0=Monday, 6=Sunday
    cron_dow = (weekday + 1) % 7
    return _field_match(pattern, cron_dow)


def start_scheduler() -> None:
    """启动定时备份调度器。"""
    global _scheduler
    if _scheduler is not None:
        return

    _scheduler = AsyncIOScheduler()
    _scheduler.add_job(
        _scan_job,
        "interval",
        minutes=1,
        id="backup_scheduled_scan",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    _scheduler.start()
    logger.info("定时备份调度器已启动（每分钟扫描）")


def stop_scheduler() -> None:
    """停止定时备份调度器。"""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("定时备份调度器已停止")


def reload_schedules() -> None:
    """在增删改任务后重新加载调度（无需重启服务）。"""
    logger.info("定时备份任务已变更，调度器将在下次扫描时自动生效")