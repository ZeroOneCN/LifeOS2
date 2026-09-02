from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import HealthCheckup
from app.schemas.health import CheckupCreate, CheckupRead

router = APIRouter()


def _checkup_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthCheckup)
        .where(HealthCheckup.check_date >= since)
        .order_by(HealthCheckup.check_date)
    ).all()

    by_item: dict[str, dict] = {}
    for r in rows:
        bucket = by_item.setdefault(
            r.item_name,
            {"item_name": r.item_name, "unit": r.unit, "reference_range": r.reference_range, "latest": None, "trend": []},
        )
        bucket["unit"] = r.unit or bucket["unit"]
        bucket["reference_range"] = r.reference_range or bucket["reference_range"]
        bucket["trend"].append(
            {"check_date": r.check_date, "value": r.value, "result": r.result}
        )
        if bucket["latest"] is None or r.check_date > bucket["latest"]["check_date"]:
            bucket["latest"] = {
                "check_date": r.check_date,
                "value": r.value,
                "result": r.result,
            }

    return {
        "items": [
            {
                **v,
                "count": len(v["trend"]),
                "latest": v["latest"],
                "trend": v["trend"][-30:],
            }
            for v in by_item.values()
        ],
        "total_count": len(rows),
        "abnormal_count": sum(
            1 for r in rows if r.result and r.result != "normal"
        ),
    }


router = crud_router(
    prefix="/health/checkup",
    tag="health-checkup",
    model=HealthCheckup,
    create_schema=CheckupCreate,
    read_schema=CheckupRead,
    order_by=HealthCheckup.check_date,
    date_column="check_date",
    stats_func=_checkup_stats,
)
