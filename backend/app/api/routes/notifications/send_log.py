"""发送日志路由：外发记录查询与统计。"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models.notification_center import NotificationSendLog

router = APIRouter(prefix="/notifications/send-logs", tags=["notification-send-logs"])


@router.get("")
def list_logs(
    notification_id: int | None = None,
    channel_type: str | None = None,
    status: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    stmt = select(NotificationSendLog)
    if notification_id is not None:
        stmt = stmt.where(NotificationSendLog.notification_id == notification_id)
    if channel_type:
        stmt = stmt.where(NotificationSendLog.channel_type == channel_type)
    if status:
        stmt = stmt.where(NotificationSendLog.status == status)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(
        stmt.order_by(NotificationSendLog.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return {"items": rows, "total": total, "page": page, "page_size": page_size}


@router.get("/stats")
def log_stats(
    days: int = Query(7, ge=1, le=90), db: Session = Depends(get_db)
):
    rows = db.scalars(select(NotificationSendLog)).all()
    total = len(rows)
    ok = sum(1 for r in rows if r.status == "sent")
    fail = sum(1 for r in rows if r.status == "failed")
    recent_fail = sum(1 for r in rows if r.status == "failed" and (r.sent_at is not None))
    return {"total": total, "sent": ok, "failed": fail, "recent_failed": recent_fail}