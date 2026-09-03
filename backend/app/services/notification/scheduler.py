"""每日提醒扫描调度器（APScheduler）。"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.core.config import settings
from app.core.database import SessionLocal

logger = logging.getLogger("app.scheduler")

_scheduler: AsyncIOScheduler | None = None


def _job() -> None:
    db = SessionLocal()
    try:
        # 提前确保种子数据存在（模板 / 功能开关）
        from app.models.notification_center import (
            FeatureReminderSetting,
            NotificationTemplate,
        )
        from app.services.notification.scanner import scan_all
        from app.services.notification.seed import ensure_seed

        ensure_seed(db)
        summary = scan_all(db)
        db.commit()
        logger.info("提醒扫描完成：%s", summary)
    except Exception as exc:  # noqa: BLE001
        logger.exception("提醒扫描失败：%s", exc)
    finally:
        db.close()


def start_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        return
    hour, minute = 8, 30
    try:
        h, m = settings.NOTIFY_SCAN_TIME.split(":")
        hour, minute = int(h), int(m)
    except Exception:
        pass

    _scheduler = AsyncIOScheduler()
    _scheduler.add_job(
        _job,
        "cron",
        hour=hour,
        minute=minute,
        id="notify_daily_scan",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    _scheduler.start()
    logger.info("通知提醒扫描已启动，每日 %02d:%02d 执行", hour, minute)


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("通知提醒扫描调度器已停止")