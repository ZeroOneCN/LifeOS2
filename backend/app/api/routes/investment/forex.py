from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import InvestmentForex
from app.schemas.investment import ForexCreate, ForexRead

router = APIRouter()


def _forex_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(InvestmentForex)
        .where(InvestmentForex.trade_date >= since)
        .order_by(InvestmentForex.trade_date)
    ).all()

    closed = [r for r in rows if r.status == "closed" and r.pnl is not None]
    wins = [r for r in closed if r.pnl > 0]
    losses = [r for r in closed if r.pnl < 0]

    daily: dict[date, float] = defaultdict(float)
    by_pair: dict[str, float] = defaultdict(float)
    for r in rows:
        if r.pnl is not None:
            daily[r.trade_date] += r.pnl
            by_pair[r.pair] += r.pnl

    return {
        "total": len(rows),
        "closed": len(closed),
        "open": sum(1 for r in rows if r.status == "open"),
        "total_pnl": round(sum(r.pnl or 0 for r in rows), 2),
        "win_rate": (
            round(len(wins) / len(closed) * 100, 1) if closed else None
        ),
        "trend": [
            {"trade_date": d, "pnl": round(p, 2)}
            for d, p in sorted(daily.items())
        ],
        "by_pair": [
            {"pair": p, "pnl": round(v, 2)}
            for p, v in sorted(by_pair.items(), key=lambda x: -x[1])
        ],
    }


router = crud_router(
    prefix="/investment/forex",
    tag="investment-forex",
    model=InvestmentForex,
    create_schema=ForexCreate,
    read_schema=ForexRead,
    order_by=InvestmentForex.trade_date,
    date_column="trade_date",
    stats_func=_forex_stats,
)
