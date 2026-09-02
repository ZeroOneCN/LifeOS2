from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinancePurchase
from app.schemas.finance import PurchaseCreate, PurchaseRead

router = APIRouter()


def _purchase_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(FinancePurchase)
        .where(FinancePurchase.purchase_date >= since)
        .order_by(FinancePurchase.purchase_date)
    ).all()

    daily: dict[date, float] = defaultdict(float)
    by_category: dict[str, float] = defaultdict(float)
    for r in rows:
        daily[r.purchase_date] += r.amount
        by_category[r.category] += r.amount

    return {
        "trend": [
            {"purchase_date": d, "amount": round(amount, 2)}
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
    prefix="/finance/purchases",
    tag="finance-purchases",
    model=FinancePurchase,
    create_schema=PurchaseCreate,
    read_schema=PurchaseRead,
    order_by=FinancePurchase.purchase_date,
    date_column="purchase_date",
    stats_func=_purchase_stats,
)
