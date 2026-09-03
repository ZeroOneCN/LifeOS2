from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    HealthBody,
    HealthCheckup,
    HealthFitness,
    HealthMedication,
    HealthReport,
    HealthSteps,
    HealthVitalsSleep,
    UserProfile,
)

router = APIRouter(prefix="/health/overview", tags=["health-overview"])


def _serialize_vitals(r: HealthVitalsSleep | None) -> dict | None:
    if r is None:
        return None
    return {
        "id": r.id,
        "record_date": r.record_date,
        "blood_pressure_high": r.blood_pressure_high,
        "blood_pressure_low": r.blood_pressure_low,
        "heart_rate": r.heart_rate,
        "blood_oxygen": r.blood_oxygen,
        "blood_glucose": r.blood_glucose,
        "body_temp": r.body_temp,
        "bedtime": r.bedtime,
        "wake_time": r.wake_time,
        "sleep_duration_min": r.sleep_duration_min,
        "deep_sleep_min": r.deep_sleep_min,
        "sleep_quality": r.sleep_quality,
    }


@router.get("")
def overview(
    db: Session = Depends(get_db), user: UserProfile = Depends(get_current_user)
) -> dict:
    today = date.today()
    week_ago = today - timedelta(days=6)

    latest_steps = db.scalars(
        select(HealthSteps)
        .where(HealthSteps.user_id == user.id)
        .order_by(HealthSteps.record_date.desc())
        .limit(1)
    ).first()
    latest_vitals = db.scalars(
        select(HealthVitalsSleep)
        .where(HealthVitalsSleep.user_id == user.id)
        .order_by(HealthVitalsSleep.record_date.desc())
        .limit(1)
    ).first()
    latest_body = db.scalars(
        select(HealthBody)
        .where(HealthBody.user_id == user.id)
        .order_by(HealthBody.record_date.desc())
        .limit(1)
    ).first()

    today_meds = db.scalars(
        select(HealthMedication)
        .where(HealthMedication.user_id == user.id)
        .where(HealthMedication.record_date == today)
    ).all()
    recent_checkup = db.scalars(
        select(HealthCheckup)
        .where(HealthCheckup.user_id == user.id)
        .order_by(HealthCheckup.check_date.desc())
        .limit(5)
    ).all()
    latest_report = db.scalars(
        select(HealthReport)
        .where(HealthReport.user_id == user.id)
        .order_by(HealthReport.report_date.desc())
        .limit(1)
    ).first()

    week_steps = db.scalars(
        select(HealthSteps)
        .where(HealthSteps.user_id == user.id)
        .where(HealthSteps.record_date >= week_ago)
    ).all()
    week_sleep = db.scalars(
        select(HealthVitalsSleep)
        .where(HealthVitalsSleep.user_id == user.id)
        .where(HealthVitalsSleep.record_date >= week_ago)
    ).all()
    week_fitness = db.scalars(
        select(HealthFitness)
        .where(HealthFitness.user_id == user.id)
        .where(HealthFitness.record_date >= week_ago)
    ).all()

    sleep_avg = None
    if week_sleep:
        durations = [r.sleep_duration_min for r in week_sleep if r.sleep_duration_min]
        sleep_avg = round(sum(durations) / len(durations)) if durations else None

    taken_meds = [m for m in today_meds if m.taken]
    return {
        "latest_steps": (
            {
                "id": latest_steps.id,
                "record_date": latest_steps.record_date,
                "steps": latest_steps.steps,
                "distance_km": latest_steps.distance_km,
                "calories": latest_steps.calories,
            }
            if latest_steps
            else None
        ),
        "latest_vitals": _serialize_vitals(latest_vitals),
        "latest_body": (
            {
                "id": latest_body.id,
                "record_date": latest_body.record_date,
                "height_cm": latest_body.height_cm,
                "weight_kg": latest_body.weight_kg,
                "bmi": latest_body.bmi,
                "body_fat_percent": latest_body.body_fat_percent,
            }
            if latest_body
            else None
        ),
        "today_medication": {
            "taken_count": len(taken_meds),
            "pending_count": len(today_meds) - len(taken_meds),
            "items": [
                {
                    "id": m.id,
                    "medicine_name": m.medicine_name,
                    "dosage": m.dosage,
                    "frequency": m.frequency,
                    "taken": m.taken,
                }
                for m in today_meds
            ],
        },
        "recent_checkup": [
            {
                "id": c.id,
                "check_date": c.check_date,
                "item_name": c.item_name,
                "value": c.value,
                "unit": c.unit,
                "result": c.result,
            }
            for c in recent_checkup
        ],
        "latest_report": (
            {
                "id": latest_report.id,
                "report_date": latest_report.report_date,
                "title": latest_report.title,
                "summary": latest_report.summary,
            }
            if latest_report
            else None
        ),
        "week_summary": {
            "steps_total": sum(r.steps for r in week_steps),
            "steps_avg": (
                round(sum(r.steps for r in week_steps) / len(week_steps))
                if week_steps
                else None
            ),
            "sleep_avg_min": sleep_avg,
            "fitness_count": len(week_fitness),
            "fitness_calories": round(
                sum(r.calories or 0 for r in week_fitness), 1
            ),
        },
    }
