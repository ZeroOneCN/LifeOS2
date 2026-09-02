from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import HealthFitness
from app.schemas.health import FitnessCreate, FitnessRead

router = APIRouter()


def _fitness_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthFitness)
        .where(HealthFitness.record_date >= since)
        .order_by(HealthFitness.record_date)
    ).all()

    by_type: dict[str, dict] = defaultdict(lambda: {"count": 0, "minutes": 0, "calories": 0.0})
    by_day: dict[date, dict] = defaultdict(lambda: {"count": 0, "minutes": 0, "calories": 0.0})
    for r in rows:
        by_type[r.exercise_type]["count"] += 1
        by_type[r.exercise_type]["minutes"] += r.duration_min
        by_type[r.exercise_type]["calories"] += r.calories or 0
        by_day[r.record_date]["count"] += 1
        by_day[r.record_date]["minutes"] += r.duration_min
        by_day[r.record_date]["calories"] += r.calories or 0

    return {
        "trend": [
            {"record_date": d, **v}
            for d, v in sorted(by_day.items())
        ],
        "by_type": [
            {"exercise_type": k, **v}
            for k, v in sorted(by_type.items(), key=lambda x: -x[1]["minutes"])
        ],
        "total_count": len(rows),
        "total_minutes": sum(r.duration_min for r in rows),
        "total_calories": round(sum(r.calories or 0 for r in rows), 1),
    }


router = crud_router(
    prefix="/health/fitness",
    tag="health-fitness",
    model=HealthFitness,
    create_schema=FitnessCreate,
    read_schema=FitnessRead,
    order_by=HealthFitness.record_date,
    date_column="record_date",
    stats_func=_fitness_stats,
)
