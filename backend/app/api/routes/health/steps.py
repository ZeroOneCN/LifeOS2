from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import HealthSteps
from app.schemas.health import StepsCreate, StepsRead

router = APIRouter()


def _steps_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthSteps)
        .where(HealthSteps.record_date >= since)
        .order_by(HealthSteps.record_date)
    ).all()

    steps = [r.steps for r in rows]
    return {
        "trend": [
            {
                "record_date": r.record_date,
                "steps": r.steps,
                "distance_km": r.distance_km,
                "calories": r.calories,
            }
            for r in rows
        ],
        "avg_steps": round(sum(steps) / len(steps)) if steps else None,
        "total_steps": sum(steps),
        "max_steps": max(steps) if steps else None,
        "record_count": len(rows),
    }


router = crud_router(
    prefix="/health/steps",
    tag="health-steps",
    model=HealthSteps,
    create_schema=StepsCreate,
    read_schema=StepsRead,
    order_by=HealthSteps.record_date,
    date_column="record_date",
    stats_func=_steps_stats,
)
