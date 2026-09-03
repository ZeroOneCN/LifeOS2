from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import Notification, UserProfile
from app.schemas.notification import NotificationCreate, NotificationRead

router = APIRouter()


def _notify_stats(db: Session, days: int, user_id: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(Notification)
        .where(
            Notification.notify_date >= since,
            Notification.user_id == user_id,
        )
        .order_by(Notification.notify_date)
    ).all()

    daily: dict[date, int] = defaultdict(int)
    by_category: dict[str, int] = defaultdict(int)
    today = date.today()
    for r in rows:
        daily[r.notify_date] += 1
        by_category[r.category] += 1

    return {
        "total": len(rows),
        "unread": sum(1 for r in rows if not r.read),
        "today": sum(1 for r in rows if r.notify_date == today),
        "by_category": [
            {"category": c, "count": n}
            for c, n in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "trend": [
            {"notify_date": d, "count": n}
            for d, n in sorted(daily.items())
        ],
    }


router = crud_router(
    prefix="/notifications",
    tag="notifications",
    model=Notification,
    create_schema=NotificationCreate,
    read_schema=NotificationRead,
    order_by=Notification.notify_date,
    date_column="notify_date",
    stats_func=_notify_stats,
)


@router.post("/read-all")
def read_all(
    db: Session = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
) -> dict:
    """将当前用户所有未读通知标记为已读。"""
    result = db.execute(
        update(Notification)
        .where(Notification.read.is_(False), Notification.user_id == current_user.id)
        .values(read=True)
    )
    db.commit()
    return {"updated": result.rowcount or 0}
