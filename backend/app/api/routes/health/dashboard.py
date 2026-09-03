from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    HealthBody,
    HealthDiet,
    HealthFitness,
    HealthSteps,
    UserProfile,
)

router = APIRouter(prefix="/health/dashboard", tags=["health-fitness-dashboard"])


@router.get("")
def dashboard(
    days: int = 30,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    since = date.today() - timedelta(days=days - 1)

    diet_rows = db.scalars(
        select(HealthDiet)
        .where(HealthDiet.user_id == user.id)
        .where(HealthDiet.record_date >= since)
    ).all()
    ex_rows = db.scalars(
        select(HealthFitness)
        .where(HealthFitness.user_id == user.id)
        .where(HealthFitness.record_date >= since)
    ).all()
    step_rows = db.scalars(
        select(HealthSteps)
        .where(HealthSteps.user_id == user.id)
        .where(HealthSteps.record_date >= since)
    ).all()
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

    # 按日汇总摄入/消耗，补全天区间
    series = []
    for d in range(days):
        key = (since + timedelta(days=d)).isoformat()
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
    step_total = sum(r.steps for r in step_rows)
    exercise_count = len(ex_rows)

    # 身体成分趋势（取有记录的最近 N 个）
    body_trend = [
        {
            "record_date": b.record_date.isoformat(),
            "weight_kg": b.weight_kg,
            "bmi": b.bmi,
            "body_fat_percent": b.body_fat_percent,
            "muscle_percent": b.muscle_percent,
        }
        for b in body_rows
    ][-30:]

    return {
        "series": series,
        "nutrition": nutrition,
        "intake_total": round(sum(intake.values()), 1),
        "expenditure_total": round(sum(cardio.values()), 1),
        "expenditure_trend": expenditure_trend,
        "step_total": step_total,
        "exercise_count": exercise_count,
        "body_trend": body_trend,
        "latest_body": body_rows[-1]
        and {
            "record_date": body_rows[-1].record_date,
            "height_cm": body_rows[-1].height_cm,
            "weight_kg": body_rows[-1].weight_kg,
            "bmi": body_rows[-1].bmi,
            "body_fat_percent": body_rows[-1].body_fat_percent,
        },
    }