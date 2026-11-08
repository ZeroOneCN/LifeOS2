"""投资域外汇统计口径用例：负净值、回撤百分比防失真、days 统一窗口过滤。"""

from datetime import date, timedelta

import pytest

from app.api.routes.investment.forex import (
    DRAWDOWN_PCT_CAP,
    compute_forex_stats,
)
from app.models import InvestmentForex, InvestmentFundRecord


def _trade(days_ago: int = 0, pnl: float = 0.0, symbol: str = "EURUSD",
           status: str = "closed", user_id: int = 1) -> InvestmentForex:
    """构造一条外汇交易记录（仅填统计用到的字段）。"""
    return InvestmentForex(
        user_id=user_id,
        trade_date=date.today() - timedelta(days=days_ago),
        symbol=symbol,
        order_type="buy",
        open_price=1.0,
        lot_size=1.0,
        commission=0.0,
        close_price=1.0,
        pnl=pnl,
        overnight_fee=0.0,
        status=status,
    )


def _fund(record_type: str, amount: float, days_ago: int = 0,
          user_id: int = 1, note: str | None = None) -> InvestmentFundRecord:
    """构造一条资金记录（入金/出金/体验金，可带备注区分失效赠金）。"""
    return InvestmentFundRecord(
        user_id=user_id,
        record_type=record_type,
        amount=amount,
        record_date=date.today() - timedelta(days=days_ago),
        note=note,
    )


def _stats(db_session, days: int = 365) -> dict:
    """按当前用户（id=1）计算统计。"""
    return compute_forex_stats(db_session, days=days, user_id=1)


def test_account_value_counts_expired_bonus_as_capital(db_session):
    """失效赠金不从本金剔除：净值 = 净投入 + 净盈亏，结果为 0.00。

    真实库同口径：6033.40 - 3242.76 + 0 - 13.91 + (-2776.73) = 0.00
    （失效赠金 -56.09 不参与扣减）。
    """
    db_session.add_all([
        _fund("deposit", 200.0),
        _fund("experience", -50.0, note="bns807 体验金失效"),
        _trade(pnl=-200.0),
    ])
    db_session.flush()

    summary = _stats(db_session)["summary"]
    # 净投入 = 200（失效赠金 -50 不扣），再加净盈亏 -200 = 0
    assert summary["account_value"] == 0.0
    assert summary["net_profit"] == -200.0
    # 展示用的体验金合计仍是带符号全量统计（含失效赠金）
    assert summary["total_experience"] == -50.0


def test_experience_loss_still_deducted_from_capital(db_session):
    """体验金亏损（bns806）仍从本金扣减，只有失效赠金不扣。"""
    db_session.add_all([
        _fund("deposit", 200.0),
        _fund("experience", -50.0, note="bns806 体验金亏损"),
        _trade(pnl=-100.0),
    ])
    db_session.flush()

    # 净投入 = 200 - 50 = 150，再加净盈亏 -100 = 50
    assert _stats(db_session)["summary"]["account_value"] == 50.0


def test_experience_bonus_not_double_counted(db_session):
    """赠金只计一次：入金 100 + 赠金 20 + 盈亏 10 = 130（旧实现会重复计成 150）。"""
    db_session.add_all([
        _fund("deposit", 100.0),
        _fund("experience", 20.0),
        _trade(pnl=10.0),
    ])
    db_session.flush()

    summary = _stats(db_session)["summary"]
    assert summary["account_value"] == 130.0


def test_drawdown_pct_when_cumulative_peak_is_zero(db_session):
    """从未盈利（累计盈亏峰值恒为 0）时，回撤百分比改用累计净投入做分母。"""
    db_session.add(_fund("deposit", 100.0))
    db_session.add_all([_trade(pnl=-30.0), _trade(pnl=-20.0)])
    db_session.flush()

    analysis = _stats(db_session)["analysis"]
    assert analysis["max_drawdown"] == 50.0
    # 50 / 100 * 100，而不是旧口径下因峰值为 0 直接返回 0
    assert analysis["max_drawdown_pct"] == 50.0


def test_drawdown_pct_with_tiny_peak_is_not_inflated(db_session):
    """峰值极小时不再出现四位数百分比：分母改用累计净投入，并受上限保护。"""
    db_session.add(_fund("deposit", 100.0))
    db_session.add_all([_trade(pnl=0.05), _trade(pnl=-100.0)])
    db_session.flush()

    analysis = _stats(db_session)["analysis"]
    assert analysis["max_drawdown"] == pytest.approx(100.0, abs=0.01)
    # 旧口径为 100 / 0.05 * 100 = 200000%；新口径为 100 / 100 * 100 = 100%
    assert analysis["max_drawdown_pct"] == 100.0
    assert analysis["max_drawdown_pct"] <= DRAWDOWN_PCT_CAP


def test_drawdown_pct_is_none_when_capital_too_small(db_session):
    """累计净投入过小时不输出百分比（None），避免分母趋零失真。"""
    db_session.add(_fund("deposit", 0.5))
    db_session.add(_trade(pnl=-1.0))
    db_session.flush()

    assert _stats(db_session)["analysis"]["max_drawdown_pct"] is None


def test_drawdown_pct_is_none_when_net_capital_is_zero(db_session):
    """没有任何资金记录（累计净投入 = 0）时，回撤百分比返回 None。"""
    db_session.add(_trade(pnl=-10.0))
    db_session.flush()

    analysis = _stats(db_session)["analysis"]
    assert analysis["max_drawdown"] == 10.0
    assert analysis["max_drawdown_pct"] is None


def test_days_filters_summary_symbol_analysis_and_funds(db_session):
    """days 对汇总、品种、回撤、时段、曲线与资金记录使用同一窗口。"""
    db_session.add_all([
        _fund("deposit", 500.0, days_ago=400),
        _fund("deposit", 100.0, days_ago=10),
        _trade(pnl=1000.0, days_ago=400, symbol="OLD"),
        _trade(pnl=-20.0, days_ago=10, symbol="NEW"),
    ])
    db_session.flush()

    recent = _stats(db_session, days=30)
    summary, analysis = recent["summary"], recent["analysis"]
    assert summary["trade_count"] == 1
    assert summary["net_profit"] == -20.0
    assert summary["total_deposit"] == 100.0
    assert summary["account_value"] == 80.0
    assert summary["symbol_count"] == 1
    assert [row["symbol"] for row in recent["by_symbol"]] == ["NEW"]
    assert recent["symbols"] == ["NEW"]
    # 窗口内只有一笔 -20，累计从 0 回落 20；分母为累计净投入 600
    assert analysis["max_drawdown"] == 20.0
    assert analysis["max_drawdown_pct"] == 3.33
    assert analysis["longest_loss_streak"] == 1
    assert analysis["longest_win_streak"] == 0
    # 曲线与逐日盈亏只保留窗口内的点
    assert [p["date"] for p in recent["equity_trend"]] == [
        (date.today() - timedelta(days=10)).isoformat()
    ]
    assert recent["equity_trend"][0]["pnl"] == -20.0
    assert len(recent["daily_pnl"]) == 1

    all_time = _stats(db_session, days=3650)
    assert all_time["summary"]["trade_count"] == 2
    assert all_time["summary"]["net_profit"] == 980.0
    assert all_time["summary"]["total_deposit"] == 600.0
    assert all_time["summary"]["account_value"] == 1580.0
    assert all_time["summary"]["symbol_count"] == 2
