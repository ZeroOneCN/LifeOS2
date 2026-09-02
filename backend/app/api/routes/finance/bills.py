from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceBill
from app.schemas.finance import BillCreate, BillRead

router = APIRouter()


def _bill_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(FinanceBill)
        .where(FinanceBill.bill_date >= since)
        .order_by(FinanceBill.bill_date)
    ).all()

    daily: dict[date, float] = defaultdict(float)
    by_type: dict[str, float] = defaultdict(float)
    for r in rows:
        daily[r.bill_date] += r.amount
        by_type[r.bill_type] += r.amount

    return {
        "trend": [
            {"bill_date": d, "amount": round(amount, 2)}
            for d, amount in sorted(daily.items())
        ],
        "by_type": [
            {"bill_type": t, "amount": round(amount, 2)}
            for t, amount in sorted(by_type.items(), key=lambda x: -x[1])
        ],
        "total": round(sum(r.amount for r in rows), 2),
        "unpaid": round(sum(r.amount for r in rows if not r.paid), 2),
        "unpaid_count": sum(1 for r in rows if not r.paid),
    }


router = crud_router(
    prefix="/finance/bills",
    tag="finance-bills",
    model=FinanceBill,
    create_schema=BillCreate,
    read_schema=BillRead,
    order_by=FinanceBill.bill_date,
    date_column="bill_date",
    stats_func=_bill_stats,
)
