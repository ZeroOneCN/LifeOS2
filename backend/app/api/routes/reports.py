"""跨模块综合报告：聚合健康、财务、生活、投资各领域的关键指标。"""

from datetime import date, timedelta
from typing import Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.finance import FinanceDebt, FinanceReminder, FinanceUtility
from app.models.health import (
    HealthCheckup,
    HealthFitness,
    HealthMedication,
    HealthSteps,
    HealthVitalsSleep,
)
from app.models.investment import InvestmentForex, InvestmentFundRecord
from app.models.lifestyle import LifestyleItem, LifestyleTodo
from app.models.user import UserProfile

router = APIRouter(prefix="/reports", tags=["reports"])


def _period_bounds(days: int) -> tuple[date, date]:
    """根据天数返回 (起始日, 结束日)；days=0 表示全部历史。"""
    today = date.today()
    if days <= 0:
        return date(2000, 1, 1), today
    return today - timedelta(days=days - 1), today


@router.get("/comprehensive")
def comprehensive_report(
    days: int = Query(30, ge=0, le=365),
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
) -> dict[str, Any]:
    """跨模块综合报告：返回指定周期内各领域的关键汇总指标。"""
    start, end = _period_bounds(days)

    # ---------- 健康 ----------
    steps_total = db.scalar(
        select(func.coalesce(func.sum(HealthSteps.steps), 0)).where(
            HealthSteps.user_id == user.id,
            HealthSteps.record_date >= start,
            HealthSteps.record_date <= end,
        )
    )
    sleep_records = db.scalars(
        select(HealthVitalsSleep.sleep_duration_min).where(
            HealthVitalsSleep.user_id == user.id,
            HealthVitalsSleep.record_date >= start,
            HealthVitalsSleep.record_date <= end,
            HealthVitalsSleep.sleep_duration_min.isnot(None),
        )
    ).all()
    sleep_avg = round(sum(sleep_records) / len(sleep_records)) if sleep_records else None
    fitness_count = db.scalar(
        select(func.count(HealthFitness.id)).where(
            HealthFitness.user_id == user.id,
            HealthFitness.record_date >= start,
            HealthFitness.record_date <= end,
        )
    )
    checkup_count = db.scalar(
        select(func.count(HealthCheckup.id)).where(
            HealthCheckup.user_id == user.id,
            HealthCheckup.check_date >= start,
            HealthCheckup.check_date <= end,
        )
    )
    med_taken = db.scalar(
        select(func.count(HealthMedication.id)).where(
            HealthMedication.user_id == user.id,
            HealthMedication.record_date >= start,
            HealthMedication.record_date <= end,
        )
    )

    # ---------- 财务 ----------
    debt_remaining = db.scalar(
        select(func.coalesce(func.sum(FinanceDebt.remaining), 0.0)).where(
            FinanceDebt.user_id == user.id,
            FinanceDebt.status == "active",
        )
    )
    pending_reminders = db.scalar(
        select(func.count(FinanceReminder.id)).where(
            FinanceReminder.user_id == user.id,
            FinanceReminder.status == "pending",
        )
    )
    unpaid_utility = db.scalar(
        select(func.count(FinanceUtility.id)).where(
            FinanceUtility.user_id == user.id,
            FinanceUtility.paid.is_(False),
        )
    )

    # ---------- 生活 ----------
    todos_done = db.scalar(
        select(func.count(LifestyleTodo.id)).where(
            LifestyleTodo.user_id == user.id,
            LifestyleTodo.done.is_(True),
            LifestyleTodo.updated_at >= start,
        )
    )
    todos_pending = db.scalar(
        select(func.count(LifestyleTodo.id)).where(
            LifestyleTodo.user_id == user.id,
            LifestyleTodo.done.is_(False),
        )
    )
    items_expiring = db.scalar(
        select(func.count(LifestyleItem.id)).where(
            LifestyleItem.user_id == user.id,
            LifestyleItem.expire_date.isnot(None),
            LifestyleItem.expire_date >= date.today(),
            LifestyleItem.expire_date <= date.today() + timedelta(days=30),
        )
    )

    # ---------- 投资 ----------
    forex_count = db.scalar(
        select(func.count(InvestmentForex.id)).where(
            InvestmentForex.user_id == user.id,
        )
    )
    fund_count = db.scalar(
        select(func.count(InvestmentFundRecord.id)).where(
            InvestmentFundRecord.user_id == user.id,
        )
    )

    return {
        "period": {"start": start.isoformat(), "end": end.isoformat(), "days": days},
        "health": {
            "steps_total": steps_total,
            "sleep_avg_min": sleep_avg,
            "fitness_count": fitness_count,
            "checkup_count": checkup_count,
            "medication_records": med_taken,
        },
        "finance": {
            "debt_remaining": float(debt_remaining or 0),
            "pending_reminders": pending_reminders,
            "unpaid_utilities": unpaid_utility,
        },
        "lifestyle": {
            "todos_done": todos_done,
            "todos_pending": todos_pending,
            "items_expiring_30d": items_expiring,
        },
        "investment": {
            "forex_records": forex_count,
            "fund_records": fund_count,
        },
    }
