from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import (
    FinanceBill,
    FinancePlan,
    FinancePurchase,
    FinanceReminder,
    FinanceTravel,
)

router = APIRouter(prefix="/finance/overview", tags=["finance-overview"])


@router.get("")
def overview(db: Session = Depends(get_db)) -> dict:
    today = date.today()
    month_start = today.replace(day=1)
    week_ago = today - timedelta(days=6)

    month_purchases = db.scalars(
        select(FinancePurchase).where(FinancePurchase.purchase_date >= month_start)
    ).all()
    month_travel = db.scalars(
        select(FinanceTravel).where(FinanceTravel.expense_date >= month_start)
    ).all()
    month_bills = db.scalars(
        select(FinanceBill).where(FinanceBill.bill_date >= month_start)
    ).all()

    pending_bills = db.scalars(
        select(FinanceBill)
        .where(FinanceBill.paid.is_(False))
        .order_by(FinanceBill.due_date)
        .limit(5)
    ).all()
    pending_reminders = db.scalars(
        select(FinanceReminder)
        .where(FinanceReminder.status == "pending")
        .order_by(FinanceReminder.due_date)
        .limit(5)
    ).all()
    active_plans = db.scalars(
        select(FinancePlan)
        .where(FinancePlan.status == "active")
        .order_by(FinancePlan.plan_date.desc())
        .limit(5)
    ).all()

    # 近 7 天支出趋势（购买 + 旅行 + 账单）
    week_rows: list[tuple[date, float]] = []
    for r in month_purchases:
        if r.purchase_date >= week_ago:
            week_rows.append((r.purchase_date, r.amount))
    for r in month_travel:
        if r.expense_date >= week_ago:
            week_rows.append((r.expense_date, r.amount))
    for r in month_bills:
        if r.bill_date >= week_ago:
            week_rows.append((r.bill_date, r.amount))

    daily: dict[date, float] = defaultdict(float)
    for d, amount in week_rows:
        daily[d] += amount

    month_expense = (
        sum(r.amount for r in month_purchases)
        + sum(r.amount for r in month_travel)
        + sum(r.amount for r in month_bills)
    )

    return {
        "month_expense": round(month_expense, 2),
        "month_purchase_count": len(month_purchases),
        "month_travel_count": len(month_travel),
        "month_bill_count": len(month_bills),
        "unpaid_bills": round(sum(r.amount for r in month_bills if not r.paid), 2),
        "week_trend": [
            {"date": d, "amount": round(amount, 2)}
            for d, amount in sorted(daily.items())
        ],
        "pending_bills": [
            {
                "id": r.id,
                "bill_type": r.bill_type,
                "amount": r.amount,
                "due_date": r.due_date,
            }
            for r in pending_bills
        ],
        "pending_reminders": [
            {
                "id": r.id,
                "title": r.title,
                "category": r.category,
                "amount": r.amount,
                "due_date": r.due_date,
            }
            for r in pending_reminders
        ],
        "active_plans": [
            {
                "id": r.id,
                "title": r.title,
                "plan_type": r.plan_type,
                "target_amount": r.target_amount,
                "saved_amount": r.saved_amount,
            }
            for r in active_plans
        ],
    }
