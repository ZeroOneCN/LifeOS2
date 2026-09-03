from collections import defaultdict

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.models import HealthBody
from app.schemas.health import BodyCreate, BodyRead

router = APIRouter()

METRIC_KEYS = [
    "weight_kg",
    "bmi",
    "body_fat_percent",
    "fat_mass_kg",
    "visceral_fat",
    "subcutaneous_fat_percent",
    "muscle_percent",
    "muscle_kg",
    "skeletal_muscle_kg",
    "water_percent",
    "protein_percent",
    "bone_kg",
]


def _latest(rows):
    if not rows:
        return None
    r = sorted(rows, key=lambda x: x.record_date, reverse=True)[0]
    bmi = r.bmi
    # 兼容历史数据：只有身高体重而无 BMI 时按公式补算
    if bmi is None and r.height_cm and r.weight_kg:
        h = r.height_cm / 100
        bmi = round(r.weight_kg / (h * h), 1)
    return {
        "id": r.id,
        "record_date": r.record_date,
        "gender": r.gender,
        "height_cm": r.height_cm,
        "weight_kg": r.weight_kg,
        "bmi": bmi,
        "body_fat_percent": r.body_fat_percent,
        "muscle_percent": r.muscle_percent,
    }


def _body_stats(db: Session, days: int, user_id: int) -> dict:
    since = days_since(days)
    stmt = select(HealthBody).where(HealthBody.user_id == user_id)
    if since is not None:
        stmt = stmt.where(HealthBody.record_date >= since)
    rows = db.scalars(
        stmt.order_by(HealthBody.record_date)
    ).all()

    trend = [{**{m: getattr(r, m) for m in METRIC_KEYS}, "record_date": r.record_date} for r in rows]
    by_date = defaultdict(list)
    for r in rows:
        by_date[r.record_date].append(r)

    changes = {}
    dates = sorted(by_date)
    if len(dates) >= 2:
        recent = by_date[dates[-1]][-1]
        prev = by_date[dates[-2]][-1]
        for m in METRIC_KEYS:
            a = getattr(recent, m)
            b = getattr(prev, m)
            if isinstance(a, (int, float)) and isinstance(b, (int, float)):
                changes[m] = round(a - b, 1)

    total_records = len(rows)
    bmi_vals = [r.bmi for r in rows if isinstance(r.bmi, (int, float))]
    weight_vals = [r.weight_kg for r in rows if isinstance(r.weight_kg, (int, float))]

    avg_bmi = round(sum(bmi_vals) / len(bmi_vals), 1) if bmi_vals else None
    avg_weight = round(sum(weight_vals) / len(weight_vals), 1) if weight_vals else None
    max_weight = max(weight_vals) if weight_vals else None
    min_weight = min(weight_vals) if weight_vals else None

    return {
        "latest": _latest(rows),
        "trend": trend,
        "changes": changes,
        "avg_bmi": avg_bmi,
        "avg_weight": avg_weight,
        "max_weight": max_weight,
        "min_weight": min_weight,
        "record_count": total_records,
    }


router = crud_router(
    prefix="/health/body",
    tag="health-body",
    model=HealthBody,
    create_schema=BodyCreate,
    read_schema=BodyRead,
    order_by=HealthBody.record_date,
    date_column="record_date",
    stats_func=_body_stats,
)