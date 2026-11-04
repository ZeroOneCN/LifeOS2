"""每日提醒扫描调度器（APScheduler）。

所有任务统一通过 ``job_runner.run_job`` 抢占 MySQL 命名锁并落库执行状态，
跨实例只会有一个执行者，拿不到锁的实例跳过本轮。
"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.orm import Session

from app.core.config import settings
from app.services.job_runner import (
    JOB_NOTIFY_OVERDUE,
    JOB_NOTIFY_SCAN,
    JOB_PHONE_SETTLE,
    JOB_SESSION_CLEANUP,
    run_job,
)

logger = logging.getLogger("app.scheduler")

_scheduler: AsyncIOScheduler | None = None


def _job(db: Session) -> None:
    """每日提醒扫描任务体。

    Args:
        db: 由任务执行器传入的数据库会话。
    """
    # 提前确保种子数据存在（模板 / 功能开关）
    from app.models.notification_center import (
        FeatureReminderSetting,
        NotificationTemplate,
    )
    from app.services.notification.scanner import scan_all
    from app.services.notification.seed import ensure_seed

    ensure_seed(db)
    summary = scan_all(db, log_activity=True)
    db.commit()
    logger.info("提醒扫描完成：%s", summary)


def _job_overdue(db: Session) -> None:
    """每小时扫描逾期网贷账单并下发提醒（去重键精确到小时，每个小时各提醒一次）。

    Args:
        db: 由任务执行器传入的数据库会话。
    """
    from app.services.notification.scanner import scan_overdue
    from app.services.notification.seed import ensure_seed

    ensure_seed(db)
    summary = scan_overdue(db, log_activity=True)
    db.commit()
    logger.info("逾期提醒扫描完成：%s", summary)


def _job_phone_settle(db: Session) -> None:
    """每日结算手机卡话费：整月一次性扣账 / 按天摊销，漏跑的天数自动补齐。

    Args:
        db: 由任务执行器传入的数据库会话。
    """
    from app.services.phone_billing import settle_all

    summary = settle_all(db, log_activity=True)
    db.commit()
    logger.info("手机卡话费结算完成：%s", summary)


def _cleanup_expired_sessions(db: Session) -> None:
    """每日清理过期的用户会话记录，防止 user_sessions 表无限膨胀。

    Args:
        db: 由任务执行器传入的数据库会话。
    """
    from datetime import datetime, timezone

    from sqlalchemy import delete, func, select

    from app.models import UserSession
    from app.services.activity import AUTO_ACTION, log_activity

    # 与 expires_at 列存储口径一致：使用「无时区 UTC」
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    # 先按用户统计待清理数量，删除后逐用户写入活动日志，保证自动化操作可追溯
    per_user = db.execute(
        select(UserSession.user_id, func.count(UserSession.id))
        .where(UserSession.expires_at < now)
        .group_by(UserSession.user_id)
    ).all()
    result = db.execute(delete(UserSession).where(UserSession.expires_at < now))
    for uid, count in per_user:
        log_activity(
            db,
            user_id=uid,
            action=AUTO_ACTION,
            module="auth/sessions",
            resource_type="session",
            summary=f"自动清理 {count} 条过期会话",
            detail={"expired_count": count, "expires_before": now.isoformat()},
        )
    db.commit()
    if result.rowcount > 0:
        logger.info("已清理 %d 条过期会话", result.rowcount)


def _run_daily_scan() -> None:
    """调度入口：抢占锁后执行每日提醒扫描。"""
    run_job(JOB_NOTIFY_SCAN, _job)


def _run_overdue_scan() -> None:
    """调度入口：抢占锁后执行逾期账单提醒扫描。"""
    run_job(JOB_NOTIFY_OVERDUE, _job_overdue)


def _run_phone_settle() -> None:
    """调度入口：抢占锁后执行手机卡话费结算。"""
    run_job(JOB_PHONE_SETTLE, _job_phone_settle)


def _run_session_cleanup() -> None:
    """调度入口：抢占锁后清理过期会话。"""
    run_job(JOB_SESSION_CLEANUP, _cleanup_expired_sessions)


def start_scheduler() -> None:
    """启动提醒、逾期、话费结算与会话清理调度器。"""
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
        _run_daily_scan,
        "cron",
        hour=hour,
        minute=minute,
        id="notify_daily_scan",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    # 每小时整点扫描逾期账单（每天每小时提醒）
    _scheduler.add_job(
        _run_overdue_scan,
        "cron",
        minute=0,
        id="notify_overdue_hourly",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    # 每日凌晨 0:30 结算手机卡话费（先于 08:30 的提醒扫描，保证余额口径最新）
    _scheduler.add_job(
        _run_phone_settle,
        "cron",
        hour=0,
        minute=30,
        id="phone_billing_settle",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    # 每日凌晨 3 点清理过期会话，避免 user_sessions 表无限增长
    _scheduler.add_job(
        _run_session_cleanup,
        "cron",
        hour=3,
        minute=0,
        id="cleanup_expired_sessions",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    _scheduler.start()
    logger.info("通知提醒扫描已启动，每日 %02d:%02d 执行", hour, minute)


def stop_scheduler() -> None:
    """停止通知提醒调度器。"""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("通知提醒扫描调度器已停止")


def is_running() -> bool:
    """返回通知提醒调度器是否正在运行。"""
    return _scheduler is not None and _scheduler.running
