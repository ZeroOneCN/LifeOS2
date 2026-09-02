from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import LifestyleSchedule
from app.schemas.lifestyle import ScheduleCreate, ScheduleRead

router = APIRouter()


def _schedule_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(LifestyleSchedule)
        .where(LifestyleSchedule.schedule_date >= since)
        .order_by(LifestyleSchedule.schedule_date)
    ).all()

    daily: dict[date, int] = defaultdict(int)
    by_category: dict[str, int] = defaultdict(int)
    for r in rows:
        daily[r.schedule_date] += 1
        if r.category:
            by_category[r.category] += 1

    return {
        "trend": [
            {"schedule_date": d, "count": n}
            for d, n in sorted(daily.items())
        ],
        "by_category": [
            {"category": c, "count": n}
            for c, n in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "total": len(rows),
    }


router = crud_router(
    prefix="/lifestyle/schedule",
    tag="lifestyle-schedule",
    model=LifestyleSchedule,
    create_schema=ScheduleCreate,
    read_schema=ScheduleRead,
    order_by=LifestyleSchedule.schedule_date,
    date_column="schedule_date",
    stats_func=_schedule_stats,
)
