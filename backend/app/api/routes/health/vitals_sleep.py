from datetime import date, timedelta
from statistics import fmean

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import HealthVitalsSleep
from app.schemas.health import VitalsSleepCreate, VitalsSleepRead

router = APIRouter()


def _vitals_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthVitalsSleep)
        .where(HealthVitalsSleep.record_date >= since)
        .order_by(HealthVitalsSleep.record_date)
    ).all()

    def avg(attr: str) -> float | None:
        values = [getattr(r, attr) for r in rows if getattr(r, attr) is not None]
        return round(fmean(values), 1) if values else None

    return {
        "trend": [
            {
                "record_date": r.record_date,
                "blood_pressure_high": r.blood_pressure_high,
                "blood_pressure_low": r.blood_pressure_low,
                "heart_rate": r.heart_rate,
                "blood_oxygen": r.blood_oxygen,
                "blood_glucose": r.blood_glucose,
                "body_temp": r.body_temp,
                "sleep_duration_min": r.sleep_duration_min,
                "deep_sleep_min": r.deep_sleep_min,
                "sleep_quality": r.sleep_quality,
            }
            for r in rows
        ],
        "avg": {
            "blood_pressure_high": avg("blood_pressure_high"),
            "blood_pressure_low": avg("blood_pressure_low"),
            "heart_rate": avg("heart_rate"),
            "blood_oxygen": avg("blood_oxygen"),
            "blood_glucose": avg("blood_glucose"),
            "body_temp": avg("body_temp"),
            "sleep_duration_min": avg("sleep_duration_min"),
            "deep_sleep_min": avg("deep_sleep_min"),
            "sleep_quality": avg("sleep_quality"),
        },
        "record_count": len(rows),
    }


router = crud_router(
    prefix="/health/vitals-sleep",
    tag="health-vitals-sleep",
    model=HealthVitalsSleep,
    create_schema=VitalsSleepCreate,
    read_schema=VitalsSleepRead,
    order_by=HealthVitalsSleep.record_date,
    date_column="record_date",
    stats_func=_vitals_stats,
)
