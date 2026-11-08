"""投资报告账户净值口径用例：失效赠金仍计入本金、赠金只计一次。"""

from datetime import date, timedelta

from app.models import InvestmentForex, InvestmentFundRecord
from app.services.investment_report import build_investment_report


def _trade(pnl: float, days_ago: int = 0, user_id: int = 1) -> InvestmentForex:
    """构造一条已平仓外汇交易。"""
    return InvestmentForex(
        user_id=user_id,
        trade_date=date.today() - timedelta(days=days_ago),
        symbol="EURUSD",
        order_type="buy",
        open_price=1.0,
        lot_size=1.0,
        commission=0.0,
        close_price=1.0,
        pnl=pnl,
        overnight_fee=0.0,
        status="closed",
    )


def _fund(record_type: str, amount: float, days_ago: int = 0,
          user_id: int = 1, note: str | None = None) -> InvestmentFundRecord:
    """构造一条资金记录。"""
    return InvestmentFundRecord(
        user_id=user_id,
        record_type=record_type,
        amount=amount,
        record_date=date.today() - timedelta(days=days_ago),
        note=note,
    )


def test_account_equity_counts_expired_bonus_as_capital(db_session):
    """账户净值 = 净投入 + 区间净盈亏；失效赠金不扣本金，结果为 0.00。"""
    db_session.add_all([
        _fund("deposit", 200.0),
        _fund("experience", -50.0, note="bns807 体验金失效"),
        _trade(pnl=-200.0),
    ])
    db_session.flush()

    start, end = date.today() - timedelta(days=30), date.today()
    _title, summary, content = build_investment_report(
        db_session, start, end, "测试", user_id=1
    )

    assert "账户净值 0.00" in summary
    overview = next(sec for sec in content if sec.get("type") == "table")
    rows = {row[0]: row[1] for row in overview["rows"]}
    assert rows["账户净值"] == "0.00"
