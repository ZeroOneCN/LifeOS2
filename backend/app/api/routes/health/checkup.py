from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.models import HealthCheckup, HealthCheckupTemplate
from app.schemas.health import (  # noqa: F401
    CheckupCreate,
    CheckupRead,
    CheckupTemplateCreate,
    CheckupTemplateRead,
)

router = APIRouter()

RESULT_LABEL = {"normal": "正常", "high": "偏高", "low": "偏低"}


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
            {
                "item_name": r.item_name,
                "unit": r.unit,
                "reference_range": r.reference_range,
                "ref_low": r.ref_low,
                "ref_high": r.ref_high,
                "latest": None,
                "trend": [],
            },
        )
        bucket["unit"] = r.unit or bucket["unit"]
        bucket["reference_range"] = r.reference_range or bucket["reference_range"]
        bucket["ref_low"] = r.ref_low if r.ref_low is not None else bucket["ref_low"]
        bucket["ref_high"] = r.ref_high if r.ref_high is not None else bucket["ref_high"]
        bucket["trend"].append({"check_date": r.check_date, "value": r.value, "result": r.result})
        if bucket["latest"] is None or r.check_date > bucket["latest"]["check_date"]:
            bucket["latest"] = {"check_date": r.check_date, "value": r.value, "result": r.result}

    abnormal_items = [
        v["latest"]
        for v in by_item.values()
        if v["latest"] and v["latest"]["result"] and v["latest"]["result"] != "normal"
    ]
    abnormal_count = len(abnormal_items)

    # 状态分布
    status_counts = {"normal": 0, "high": 0, "low": 0}
    for v in by_item.values():
        if v["latest"] and v["latest"]["result"]:
            status_counts[v["latest"]["result"]] += 1

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
        "abnormal_count": abnormal_count,
        "status_counts": status_counts,
        "abnormal_items": abnormal_items,
        "status_label": RESULT_LABEL,
    }


# ---- 体检指标记录 CRUD ----
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


# ---- 体检标准模板 ----
template_router = crud_router(
    prefix="/health/checkup/templates",
    tag="health-checkup-template",
    model=HealthCheckupTemplate,
    create_schema=CheckupTemplateCreate,
    read_schema=CheckupTemplateRead,
    order_by=HealthCheckupTemplate.item_name,
)
router.include_router(template_router)