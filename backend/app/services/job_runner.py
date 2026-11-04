"""定时任务统一抢占与执行状态落库。

抢占机制：MySQL 命名锁 ``GET_LOCK('lifeos:job:<name>', 0)``。
- 单库方案，无需额外中间件，跨实例有效；
- 超时为 0，抢不到立即跳过本轮（记录 skipped），不会堆积等待；
- 命名锁随连接释放，进程异常退出时数据库自动清理，无需兜底定时任务。

四个（以及其余）应用内定时任务统一通过 :func:`run_job` 执行，执行结果写入
``scheduled_job_state``，每次执行覆盖同一 job 的最近状态。
"""

import logging
from contextlib import contextmanager
from datetime import datetime
from typing import Callable, Iterator

from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.database import SessionLocal, engine
from app.models.job_run import ScheduledJobState

logger = logging.getLogger("app.job_runner")

# 任务名常量：调度器与健康检查共用，避免字符串散落
JOB_BACKUP_SCAN = "backup_scheduled_scan"
JOB_MONTHLY_REPORT = "monthly_report_generate"
JOB_NOTIFY_SCAN = "notify_daily_scan"
JOB_NOTIFY_OVERDUE = "notify_overdue_hourly"
JOB_PHONE_SETTLE = "phone_billing_settle"
JOB_SESSION_CLEANUP = "cleanup_expired_sessions"

LOCK_PREFIX = "lifeos:job:"
LOCK_TIMEOUT_SECONDS = 0
ERROR_SUMMARY_MAX = 200


@contextmanager
def job_lock(job_name: str) -> Iterator[bool]:
    """以 MySQL 命名锁尝试抢占任务。

    Args:
        job_name: 任务唯一名。

    Yields:
        True 表示抢到锁，可以执行；False 表示其他实例正在执行，本轮应跳过。
    """
    lock_name = f"{LOCK_PREFIX}{job_name}"

    # MySQL 命名锁作用域为整个库，非 MySQL 环境（如单进程 SQLite 开发）直接放行
    if engine.dialect.name != "mysql":
        yield True
        return

    # GET_LOCK 绑定连接：必须用同一连接执行锁操作与后续释放，结束后归还连接池
    conn = engine.connect()
    acquired = False
    try:
        result = conn.execute(
            text("SELECT GET_LOCK(:name, :timeout)"),
            {"name": lock_name, "timeout": LOCK_TIMEOUT_SECONDS},
        ).scalar()
        acquired = result == 1
        yield acquired
    finally:
        try:
            if acquired:
                conn.execute(text("SELECT RELEASE_LOCK(:name)"), {"name": lock_name})
        finally:
            conn.close()


def run_job(
    job_name: str,
    func: Callable[[Session], None],
    *,
    session_factory: Callable[[], Session] = SessionLocal,
) -> str:
    """抢占并执行定时任务，同时落库执行状态。

    Args:
        job_name: 任务唯一名。
        func: 任务函数，接收一个数据库会话；抛异常视为执行失败。
        session_factory: 会话工厂（测试可注入）。

    Returns:
        本次执行结果：``success`` / ``failed`` / ``skipped``。异常不会向外抛出，
        以免单个任务失败导致调度器线程退出。
    """
    started = datetime.now()
    try:
        with job_lock(job_name) as acquired:
            if not acquired:
                logger.info("定时任务 %s 未抢到执行锁，本轮跳过", job_name)
                _record_state(
                    job_name, "skipped", started, datetime.now(), 0, None, session_factory
                )
                return "skipped"
            return _execute(job_name, func, started, session_factory)
    except Exception as exc:  # noqa: BLE001 - 锁连接异常也不能让调度器崩溃
        logger.exception("定时任务 %s 抢占或执行异常", job_name)
        _record_state(
            job_name, "failed", started, datetime.now(), 0, str(exc), session_factory
        )
        return "failed"


def _execute(
    job_name: str,
    func: Callable[[Session], None],
    started: datetime,
    session_factory: Callable[[], Session],
) -> str:
    """在已持有锁的情况下执行任务并记录状态。

    Args:
        job_name: 任务唯一名。
        func: 任务函数。
        started: 开始时间。
        session_factory: 会话工厂。

    Returns:
        ``success`` 或 ``failed``。
    """
    db = session_factory()
    status = "success"
    error: str | None = None
    try:
        func(db)
        db.commit()
    except Exception as exc:  # noqa: BLE001 - 任务失败只记录状态，不向上抛出
        status = "failed"
        error = str(exc)
        logger.exception("定时任务 %s 执行失败", job_name)
        try:
            db.rollback()
        except SQLAlchemyError:
            logger.exception("定时任务 %s 回滚失败", job_name)
    finally:
        db.close()

    finished = datetime.now()
    _record_state(
        job_name,
        status,
        started,
        finished,
        int((finished - started).total_seconds() * 1000),
        error,
        session_factory,
    )
    return status


def _record_state(
    job_name: str,
    status: str,
    started: datetime,
    finished: datetime,
    duration_ms: int,
    error: str | None,
    session_factory: Callable[[], Session],
) -> None:
    """更新任务最近一次执行状态（每个 job 一行）；落库失败只记录日志。

    Args:
        job_name: 任务唯一名。
        status: success / failed / skipped。
        started: 开始时间。
        finished: 结束时间。
        duration_ms: 耗时（毫秒）。
        error: 错误原文，仅截断后保存，不存堆栈。
        session_factory: 会话工厂。
    """
    summary = error[:ERROR_SUMMARY_MAX] if error else None
    db = session_factory()
    try:
        row = db.scalar(
            select(ScheduledJobState).where(ScheduledJobState.job_name == job_name)
        )
        if row is None:
            row = ScheduledJobState(job_name=job_name)
            db.add(row)
        row.status = status
        row.started_at = started
        row.finished_at = finished
        row.duration_ms = duration_ms
        row.error_summary = summary
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        logger.exception("定时任务 %s 状态落库失败", job_name)
    finally:
        db.close()


def get_job_states() -> dict[str, dict]:
    """读取各任务最近一次执行状态，供健康检查使用。

    kwargs:
        无。

    Returns:
        任务名到状态字典的映射；仅包含状态、起止时间与耗时，不含错误原文。
        表不存在或读取失败时返回空字典（不影响健康接口可用性）。
    """
    db = SessionLocal()
    try:
        rows = db.scalars(select(ScheduledJobState).order_by(ScheduledJobState.job_name)).all()
        return {
            row.job_name: {
                "status": row.status,
                "started_at": row.started_at.isoformat() if row.started_at else None,
                "finished_at": row.finished_at.isoformat() if row.finished_at else None,
                "duration_ms": row.duration_ms,
            }
            for row in rows
        }
    except SQLAlchemyError:
        logger.warning("读取定时任务执行状态失败（迁移是否已执行？）", exc_info=True)
        return {}
    finally:
        db.close()
