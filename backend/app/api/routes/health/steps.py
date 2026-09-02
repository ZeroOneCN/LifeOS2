from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.models import HealthStepSetting, HealthSteps
from app.schemas.health import StepSettingCreate, StepSettingRead, StepsCreate, StepsRead

router = APIRouter()


def _get_setting(db: Session) -> HealthStepSetting:
    setting = db.get(HealthStepSetting, 1)
    if not setting:
        setting = HealthStepSetting(id=1, stride_cm=70.0)
        db.add(setting)
        db.commit()
        db.refresh(setting)
    return setting


def _register_fixed(router) -> None:
    """注册固定静态路由，需在动态路由 /{item_id} 之前。"""

    @router.get("/settings", response_model=StepSettingRead)
    def get_settings(db: Session = Depends(get_db)):
        return _get_setting(db)

    @router.put("/settings", response_model=StepSettingRead)
    def update_settings(payload: StepSettingCreate, db: Session = Depends(get_db)):
        setting = _get_setting(db)
        setting.stride_cm = payload.stride_cm
        db.commit()
        db.refresh(setting)
        return setting

    @router.get("/monthly")
    def monthly_stats(db: Session = Depends(get_db)):
        """按自然月统计步数（近 12 个月）。"""
        rows = db.scalars(select(HealthSteps).order_by(HealthSteps.record_date)).all()
        by_month: dict[str, dict] = defaultdict(lambda: {"steps": 0, "distance_km": 0.0, "days": set()})
        for r in rows:
            key = r.record_date.strftime("%Y-%m")
            by_month[key]["steps"] += r.steps
            by_month[key]["distance_km"] += r.distance_km or 0
            by_month[key]["days"].add(r.record_date)
        return {
            "months": [
                {"month": k, "steps": v["steps"], "distance_km": round(v["distance_km"], 2), "days": len(v["days"])}
                for k, v in sorted(by_month.items())[-12:]
            ]
        }


def _steps_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthSteps)
        .where(HealthSteps.record_date >= since)
        .order_by(HealthSteps.record_date, HealthSteps.id)
    ).all()

    by_day: dict[date, dict] = defaultdict(lambda: {"steps": 0, "distance_km": 0.0, "calories": 0.0})
    by_period: dict[str, int] = defaultdict(int)
    for r in rows:
        by_day[r.record_date]["steps"] += r.steps
        by_day[r.record_date]["distance_km"] += r.distance_km or 0
        by_day[r.record_date]["calories"] += r.calories or 0
        by_period[r.period] += r.steps

    steps_list = [by_day[d]["steps"] for d in by_day]
    total_steps = sum(steps_list)

    return {
        "trend": [
            {
                "record_date": d,
                "steps": v["steps"],
                "distance_km": round(v["distance_km"], 2),
                "calories": round(v["calories"], 1),
            }
            for d, v in sorted(by_day.items())
        ],
        "by_period": [
            {"period": k, "steps": v}
            for k, v in sorted(by_period.items(), key=lambda x: x[0])
        ],
        "avg_steps": round(total_steps / len(by_day)) if by_day else None,
        "max_steps": max(steps_list) if steps_list else None,
        "total_steps": total_steps,
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
    extra_routes=_register_fixed,
)