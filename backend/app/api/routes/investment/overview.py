from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.routes.investment.forex import compute_forex_stats
from app.core.database import get_db
from app.models import InvestmentFundRecord, InvestmentForex, InvestmentReport

router = APIRouter(prefix="/investment/overview", tags=["investment-overview"])


@router.get("")
def overview(db: Session = Depends(get_db)):
    stats = compute_forex_stats(db, days=365)
    report_count = db.scalar(select(func.count()).select_from(select(InvestmentReport).subquery())) or 0
    total_records = db.scalar(select(func.count()).select_from(select(InvestmentForex).subquery())) or 0
    fund_count = db.scalar(select(func.count()).select_from(select(InvestmentFundRecord).subquery())) or 0

    summary = stats["summary"]
    analysis = stats["analysis"]

    return {
        "summary": summary,
        "analysis": analysis,
        "equity_trend": stats["equity_trend"],
        "daily_pnl": stats["daily_pnl"],
        "by_symbol": stats["by_symbol"],
        "symbols": stats["symbols"],
        "report_count": report_count,
        "total_records": total_records,
        "fund_count": fund_count,
    }