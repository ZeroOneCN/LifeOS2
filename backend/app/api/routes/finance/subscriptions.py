from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceSubscription
from app.schemas.finance import SubscriptionCreate, SubscriptionRead


def _add_months(d: date, months: int) -> date:
    y = d.year + (d.month - 1 + months) // 12
    m = (d.month - 1 + months) % 12 + 1
    day = min(d.day, _days_in_month(y, m))
    return date(y, m, day)


def _days_in_month(y: int, m: int) -> int:
    import calendar

    return calendar.monthrange(y, m)[1]


def _cycle_months(cycle: str) -> int:
    return {"month": 1, "quarter": 3, "year": 12}.get(cycle, 1)


def _next_renewal(start: date, cycle: str, ref: date) -> date:
    months = _cycle_months(cycle)
    n = start
    while n <= ref:
        n = _add_months(n, months)
    return n


def _subs_stats(db: Session, days: int, user_id: int) -> dict:
    today = date.today()
    rows = db.scalars(
        select(FinanceSubscription).where(FinanceSubscription.user_id == user_id)
    ).all()
    active = [r for r in rows if r.status == "active"]

    total_active = sum(r.amount for r in active)
    by_category: dict[str, float] = {}
    for r in active:
        by_category[r.category] = by_category.get(r.category, 0.0) + r.amount

    upcoming = []
    for r in active:
        next_renewal = _next_renewal(r.start_date, r.billing_cycle, today)
        if (next_renewal - today).days <= r.remind_days:
            upcoming.append(
                {
                    "id": r.id,
                    "name": r.name,
                    "category": r.category,
                    "amount": r.amount,
                    "next_renewal": next_renewal.isoformat(),
                    "remind_days": r.remind_days,
                }
            )
    upcoming.sort(key=lambda x: x["next_renewal"])

    return {
        "total_active": round(total_active, 2),
        "active_count": len(active),
        "total_count": len(rows),
        "by_category": [
            {"category": c, "amount": round(a, 2)}
            for c, a in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "upcoming": upcoming,
    }


router = crud_router(
    prefix="/finance/subscriptions",
    tag="finance-subscriptions",
    model=FinanceSubscription,
    create_schema=SubscriptionCreate,
    read_schema=SubscriptionRead,
    order_by=FinanceSubscription.start_date,
    date_column="start_date",
    stats_func=_subs_stats,
)