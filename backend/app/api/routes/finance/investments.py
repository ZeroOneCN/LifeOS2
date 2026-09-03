from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceInvestment
from app.schemas.finance import InvestmentCreate, InvestmentRead


def _inv_stats(db: Session, days: int, user_id: int) -> dict:
    rows = db.scalars(
        select(FinanceInvestment).where(FinanceInvestment.user_id == user_id)
    ).all()
    total_pnl = sum(r.pnl for r in rows)
    by_category: dict[str, float] = {}
    by_platform: dict[str, float] = {}
    for r in rows:
        by_category[r.category] = by_category.get(r.category, 0.0) + r.pnl
        by_platform[r.platform] = by_platform.get(r.platform, 0.0) + r.pnl
    return {
        "count": len(rows),
        "total_pnl": round(total_pnl, 2),
        "profit": round(sum(r.pnl for r in rows if r.pnl > 0), 2),
        "loss": round(sum(r.pnl for r in rows if r.pnl < 0), 2),
        "by_category": [
            {"category": c, "amount": round(a, 2)}
            for c, a in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "by_platform": [
            {"platform": p, "amount": round(a, 2)}
            for p, a in sorted(by_platform.items(), key=lambda x: -x[1])
        ],
    }


router = crud_router(
    prefix="/finance/investments",
    tag="finance-investments",
    model=FinanceInvestment,
    create_schema=InvestmentCreate,
    read_schema=InvestmentRead,
    order_by=FinanceInvestment.id,
    stats_func=_inv_stats,
)