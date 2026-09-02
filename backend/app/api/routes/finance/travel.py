from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceTravel
from app.schemas.finance import TravelCreate, TravelRead

router = APIRouter()


def _travel_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(FinanceTravel)
        .where(FinanceTravel.expense_date >= since)
        .order_by(FinanceTravel.expense_date)
    ).all()

    daily: dict[date, float] = defaultdict(float)
    by_category: dict[str, float] = defaultdict(float)
    for r in rows:
        daily[r.expense_date] += r.amount
        by_category[r.category] += r.amount

    return {
        "trend": [
            {"expense_date": d, "amount": round(amount, 2)}
            for d, amount in sorted(daily.items())
        ],
        "by_category": [
            {"category": c, "amount": round(amount, 2)}
            for c, amount in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "total": round(sum(r.amount for r in rows), 2),
        "count": len(rows),
    }


router = crud_router(
    prefix="/finance/travel",
    tag="finance-travel",
    model=FinanceTravel,
    create_schema=TravelCreate,
    read_schema=TravelRead,
    order_by=FinanceTravel.expense_date,
    date_column="expense_date",
    stats_func=_travel_stats,
)
