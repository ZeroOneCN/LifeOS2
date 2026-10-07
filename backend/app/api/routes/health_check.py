"""健康检查接口：返回数据库连通性、磁盘空间、定时调度器运行状态。"""

import shutil
from datetime import datetime, timezone

from fastapi import APIRouter
from sqlalchemy import text

from app.core.database import engine
from app.services.backup_scheduler import is_running as backup_running
from app.services.notification.scheduler import is_running as notify_running

router = APIRouter(tags=["health-check"])


def _check_database() -> tuple[bool, str]:
    """检测数据库连通性，返回 (是否正常, 描述)。"""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True, "ok"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def _check_disk() -> dict[str, int | float]:
    """检测数据盘空间，返回总容量/已用/可用（字节）与使用率百分比。"""
    try:
        usage = shutil.disk_usage("/")
        return {
            "total": usage.total,
            "used": usage.used,
            "free": usage.free,
            "percent": round(usage.used / usage.total * 100, 1),
        }
    except Exception:  # noqa: BLE001
        return {"total": 0, "used": 0, "free": 0, "percent": 0.0}


@router.get("/health")
def health_check() -> dict:
    """健康检查：返回数据库、磁盘、调度器状态，任一关键项异常时 status 为 degraded。"""
    db_ok, db_msg = _check_database()
    disk = _check_disk()
    notify_ok = notify_running()
    backup_ok = backup_running()

    overall = "ok" if (db_ok and notify_ok and backup_ok) else "degraded"

    return {
        "status": overall,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "database": {"status": "ok" if db_ok else "error", "detail": db_msg},
        "disk": disk,
        "schedulers": {
            "notification": "running" if notify_ok else "stopped",
            "backup": "running" if backup_ok else "stopped",
        },
    }
