from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import HealthStepSetting, HealthSteps, UserProfile
from app.schemas.health import StepSettingCreate, StepSettingRead, StepsCreate, StepsRead

router = APIRouter()


def _get_setting(db: Session, user_id: int) -> HealthStepSetting:
    setting = db.scalar(
        select(HealthStepSetting).where(HealthStepSetting.user_id == user_id)
    )
    if not setting:
        setting = HealthStepSetting(stride_cm=70.0, user_id=user_id)
        db.add(setting)
        db.commit()
        db.refresh(setting)
    return setting


def _register_fixed(router) -> None:
    """注册固定静态路由，需在动态路由 /{item_id} 之前。"""

    @router.get("/settings", response_model=StepSettingRead)
    def get_settings(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        return _get_setting(db, user.id)

    @router.put("/settings", response_model=StepSettingRead)
    def update_settings(
        payload: StepSettingCreate,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        setting = _get_setting(db, user.id)
        setting.stride_cm = payload.stride_cm
        # 步幅变更后，按新步幅实时重算所有记录的距离
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .where(HealthSteps.steps.isnot(None))
        ).all()
        for r in rows:
            r.distance_km = round(r.steps * payload.stride_cm / 100000, 2)
        db.commit()
        db.refresh(setting)
        return setting

    @router.get("/monthly")
    def monthly_stats(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """按自然月统计步数（近 12 个月）。"""
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .order_by(HealthSteps.record_date)
        ).all()
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

    @router.get("/daily-summary")
    def daily_summary(
        year: int | None = Query(None),
        month: int | None = Query(None),
        page: int = Query(1, ge=1),
        page_size: int = Query(8, ge=1, le=31),
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """指定月份的每日步数汇总（按天累加所有时间段），默认当月，按页返回（默认每页 8 天）。"""
        today = date.today()
        y = year or today.year
        m = month or today.month
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .where(func.month(HealthSteps.record_date) == m)
            .where(func.year(HealthSteps.record_date) == y)
            .order_by(HealthSteps.record_date)
        ).all()
        by_day: dict[date, dict] = defaultdict(lambda: {"steps": 0, "distance_km": 0.0, "calories": 0.0})
        for r in rows:
            by_day[r.record_date]["steps"] += r.steps
            by_day[r.record_date]["distance_km"] += r.distance_km or 0
            by_day[r.record_date]["calories"] += r.calories or 0
        days = sorted(by_day.items(), key=lambda x: x[0], reverse=True)
        total = len(days)
        start = (page - 1) * page_size
        current = days[start:start + page_size]
        return {
            "month": f"{y}-{m:02d}",
            "items": [
                {
                    "record_date": d,
                    "steps": v["steps"],
                    "distance_km": round(v["distance_km"], 2),
                    "calories": round(v["calories"], 1),
                }
                for d, v in current
            ],
            "total": total,
            "page": page,
            "page_size": page_size,
        }


def _steps_stats(db: Session, days: int, user_id: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthSteps)
        .where(HealthSteps.user_id == user_id)
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