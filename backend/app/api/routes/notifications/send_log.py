"""发送日志路由：外发记录查询与统计。"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.models.notification import Notification
from app.models.notification_center import NotificationChannel, NotificationSendLog

router = APIRouter(prefix="/notifications/send-logs", tags=["notification-send-logs"])


@router.get("")
def list_logs(
    notification_id: int | None = None,
    channel_type: str | None = None,
    status: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    stmt = select(NotificationSendLog).where(
        NotificationSendLog.user_id == current_user.id
    )
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

    # 补充渠道名称与关联通知信息，供前端点击查看详情
    channel_ids = {r.channel_id for r in rows if r.channel_id}
    channels: dict[int, str] = {}
    if channel_ids:
        channels = {
            c.id: c.name
            for c in db.scalars(
                select(NotificationChannel).where(
                    NotificationChannel.id.in_(channel_ids),
                    NotificationChannel.user_id == current_user.id,
                )
            ).all()
        }
    notif_ids = {r.notification_id for r in rows if r.notification_id}
    notifs: dict[int, Notification] = {}
    if notif_ids:
        notifs = {
            n.id: n
            for n in db.scalars(
                select(Notification).where(
                    Notification.id.in_(notif_ids),
                    Notification.user_id == current_user.id,
                )
            ).all()
        }

    items = []
    for r in rows:
        n = notifs.get(r.notification_id)
        items.append(
            {
                "id": r.id,
                "notification_id": r.notification_id,
                "channel_type": r.channel_type,
                "channel_id": r.channel_id,
                "channel_name": channels.get(r.channel_id),
                "status": r.status,
                "error": r.error,
                "sent_at": r.sent_at,
                "created_at": r.created_at,
                "notification": (
                    {
                        "title": n.title,
                        "content": n.content,
                        "category": n.category,
                        "source": n.source,
                        "notify_date": (
                            n.notify_date.isoformat() if n.notify_date else None
                        ),
                    }
                    if n
                    else None
                ),
            }
        )
    return {"items": items, "total": total, "page": page, "page_size": page_size}


@router.get("/stats")
def log_stats(
    days: int = Query(7, ge=1, le=90),
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.scalars(
        select(NotificationSendLog).where(
            NotificationSendLog.user_id == current_user.id
        )
    ).all()
    total = len(rows)
    ok = sum(1 for r in rows if r.status == "sent")
    fail = sum(1 for r in rows if r.status == "failed")
    recent_fail = sum(1 for r in rows if r.status == "failed" and (r.sent_at is not None))
    return {"total": total, "sent": ok, "failed": fail, "recent_failed": recent_fail}