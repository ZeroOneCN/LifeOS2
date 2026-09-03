from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.api.crud import days_since
from app.models import (
    HealthBody,
    HealthDiet,
    HealthFitness,
    HealthSteps,
    UserProfile,
)

router = APIRouter(prefix="/health/dashboard", tags=["health-fitness-dashboard"])


def _calc_bmi(b) -> float | None:
    """返回身体记录的 BMI：已存值优先；否则按身高体重实时计算。"""
    if b is None:
        return None
    if b.bmi is not None:
        return b.bmi
    if b.height_cm and b.weight_kg:
        h = b.height_cm / 100
        return round(b.weight_kg / (h * h), 1)
    return None


@router.get("")
def dashboard(
    days: int = 30,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    since = days_since(days)
    has_window = since is not None

    stmt_diet = select(HealthDiet).where(HealthDiet.user_id == user.id)
    if has_window:
        stmt_diet = stmt_diet.where(HealthDiet.record_date >= since)
    diet_rows = db.scalars(stmt_diet).all()

    stmt_ex = select(HealthFitness).where(HealthFitness.user_id == user.id)
    if has_window:
        stmt_ex = stmt_ex.where(HealthFitness.record_date >= since)
    ex_rows = db.scalars(stmt_ex).all()

    stmt_step = select(HealthSteps).where(HealthSteps.user_id == user.id)
    if has_window:
        stmt_step = stmt_step.where(HealthSteps.record_date >= since)
    step_rows = db.scalars(stmt_step).all()

    body_rows = db.scalars(
        select(HealthBody)
        .where(HealthBody.user_id == user.id)
        .order_by(HealthBody.record_date)
    ).all()

    intake = defaultdict(float)
    cardio = defaultdict(float)  # 运动消耗
    for r in diet_rows:
        intake[r.record_date.isoformat()] += r.calories or 0
    for r in ex_rows:
        cardio[r.record_date.isoformat()] += r.calories or 0

    # 按日汇总摄入/消耗，补全天区间（days>0 用窗口，否则用实际记录日期范围）
    all_days = sorted(set(list(intake.keys()) + list(cardio.keys())))
    if has_window:
        day_keys = [(since + timedelta(days=d)).isoformat() for d in range(days)]
    else:
        day_keys = all_days
        if not day_keys:
            day_keys = [date.today().isoformat()]
    series = []
    for key in day_keys:
        series.append(
            {
                "record_date": key,
                "intake": round(intake.get(key, 0), 1),
                "expenditure": round(cardio.get(key, 0), 1),
                "balance": round(intake.get(key, 0) - cardio.get(key, 0), 1),
            }
        )

    # 营养总量
    nutrition = {
        "calories": round(sum(r.calories or 0 for r in diet_rows), 1),
        "protein": round(sum(r.protein or 0 for r in diet_rows), 1),
        "carbs": round(sum(r.carbs or 0 for r in diet_rows), 1),
        "fat": round(sum(r.fat or 0 for r in diet_rows), 1),
    }
    # 每日运动消耗趋势
    ex_by_day = defaultdict(float)
    for r in ex_rows:
        ex_by_day[r.record_date] += r.calories or 0
    expenditure_trend = [
        {"record_date": d.isoformat(), "calories": round(v, 1)}
        for d, v in sorted(ex_by_day.items())
    ]
    # 步数总数：每日取最大值后再求和（与步数页口径一致，避免同天多时段累计条目重复累加）
    step_day_max: dict = {}
    for r in step_rows:
        steps = r.steps or 0
        cur = step_day_max.get(r.record_date)
        if cur is None or steps > cur:
            step_day_max[r.record_date] = steps
    step_total = sum(step_day_max.values())
    exercise_count = len(ex_rows)

    # 身体成分趋势（取有记录的最近 N 个）
    body_trend = [
        {
            "record_date": b.record_date.isoformat(),
            "weight_kg": b.weight_kg,
            "bmi": _calc_bmi(b),
            "body_fat_percent": b.body_fat_percent,
            "muscle_percent": b.muscle_percent,
        }
        for b in body_rows
    ][-30:]

    latest_body = body_rows[-1] if body_rows else None

    return {
        "series": series,
        "nutrition": nutrition,
        "intake_total": round(sum(intake.values()), 1),
        "expenditure_total": round(sum(cardio.values()), 1),
        "expenditure_trend": expenditure_trend,
        "step_total": step_total,
        "exercise_count": exercise_count,
        "body_trend": body_trend,
        "latest_body": latest_body
        and {
            "record_date": latest_body.record_date,
            "height_cm": latest_body.height_cm,
            "weight_kg": latest_body.weight_kg,
            "bmi": _calc_bmi(latest_body),
            "body_fat_percent": latest_body.body_fat_percent,
        },
    }