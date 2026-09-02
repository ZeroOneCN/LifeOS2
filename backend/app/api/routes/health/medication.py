from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import HealthMedication
from app.schemas.health import MedicationCreate, MedicationRead

router = APIRouter()


def _medication_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthMedication)
        .where(HealthMedication.record_date >= since)
        .order_by(HealthMedication.record_date)
    ).all()

    today = date.today()
    today_items = [r for r in rows if r.record_date == today]
    taken = [r for r in today_items if r.taken]

    by_day: dict[date, dict] = defaultdict(lambda: {"total": 0, "taken": 0})
    for r in rows:
        by_day[r.record_date]["total"] += 1
        if r.taken:
            by_day[r.record_date]["taken"] += 1

    total_records = len(rows)
    taken_records = sum(1 for r in rows if r.taken)
    return {
        "today": {
            "taken_count": len(taken),
            "pending_count": len(today_items) - len(taken),
            "items": [
                {
                    "id": r.id,
                    "medicine_name": r.medicine_name,
                    "dosage": r.dosage,
                    "frequency": r.frequency,
                    "taken": r.taken,
                }
                for r in today_items
            ],
        },
        "adherence_rate": (
            round(taken_records / total_records * 100, 1) if total_records else None
        ),
        "trend": [
            {"record_date": d, **v}
            for d, v in sorted(by_day.items())
        ],
        "total_count": total_records,
    }


router = crud_router(
    prefix="/health/medication",
    tag="health-medication",
    model=HealthMedication,
    create_schema=MedicationCreate,
    read_schema=MedicationRead,
    order_by=HealthMedication.record_date,
    date_column="record_date",
    stats_func=_medication_stats,
)
