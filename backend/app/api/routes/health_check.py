"""健康检查接口：匿名可访问，只暴露最小化状态信息。

对外仅返回整体状态、数据库连通性（ok/error）与各调度器运行状态；
数据库异常原文、磁盘用量等内部细节不再返回，异常详情只写服务端日志。
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter
from sqlalchemy import text

from app.core.database import engine
from app.services import backup_scheduler, report_scheduler
from app.services.job_runner import get_job_states
from app.services.notification import scheduler as notification_scheduler

router = APIRouter(tags=["health-check"])

logger = logging.getLogger("app.health")


def _check_database() -> bool:
    """检测数据库连通性。

    kwargs:
        无。

    Returns:
        True 表示数据库可执行 ``SELECT 1``；False 表示连接或执行失败（原因仅记录日志）。
    """
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:  # noqa: BLE001 - 健康检查需兜住所有异常，避免接口本身 500
        logger.exception("健康检查数据库连通性检测失败")
        return False


def _scheduler_status() -> dict[str, str]:
    """汇总三个调度器的运行状态。

    kwargs:
        无。

    Returns:
        调度器名到 ``running`` / ``stopped`` 的映射。
    """
    return {
        "notification": "running" if notification_scheduler.is_running() else "stopped",
        "backup": "running" if backup_scheduler.is_running() else "stopped",
        "report": "running" if report_scheduler.is_running() else "stopped",
    }


def _job_status() -> dict[str, dict]:
    """读取各定时任务最近一次执行状态（不含错误原文）。

    kwargs:
        无。

    Returns:
        任务名到状态摘要的映射；读取失败时返回空字典，保证健康接口不因此 500。
    """
    try:
        return get_job_states()
    except Exception:  # noqa: BLE001 - 健康检查必须兜住所有异常
        logger.exception("健康检查读取定时任务执行状态失败")
        return {}


@router.get("/health")
def health_check() -> dict:
    """健康检查：返回整体状态、数据库状态、调度器状态与任务最近执行结果。

    kwargs:
        无。

    Returns:
        最小化健康信息字典；数据库或任一调度器异常时整体状态为 ``degraded``。
    """
    db_ok = _check_database()
    schedulers = _scheduler_status()
    overall = "ok" if db_ok and all(v == "running" for v in schedulers.values()) else "degraded"

    return {
        "status": overall,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "database": {"status": "ok" if db_ok else "error"},
        "schedulers": schedulers,
        "jobs": _job_status(),
    }
