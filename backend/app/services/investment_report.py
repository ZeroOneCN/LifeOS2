from collections import defaultdict
from datetime import date, datetime, time

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import InvestmentForex, InvestmentFundRecord

# 失效赠金记录（体验金失效）备注前缀：这类负数不从本金里剔除
EXPIRED_BONUS_MARK = "bns807"


def is_expired_bonus(note: str | None) -> bool:
    """判断一条体验金记录是否为「失效赠金」。

    Args:
        note: 资金记录备注。

    Returns:
        备注含 bns807 时返回 True，否则 False。
    """
    return bool(note) and EXPIRED_BONUS_MARK in note


def net_capital_of(funds) -> float:
    """按统一业务口径计算净投入（与外汇统计共用）。

    净投入 = 入金 - 出金 + 赠金发放 - 体验金亏损。
    其中：
    - 失效赠金（备注含 bns807）**不从本金里剔除**，等价于仍计入本金；
    - 赠金只在体验金记录这一处计一次（发放为正、亏损为负），
      不再额外叠加「剩余赠金余额」，避免 bonus 与 remaining_bonus 重复计价。

    真实库代入：6033.40 - 3242.76 + 0 - 13.91 = 2776.73。

    Args:
        funds: InvestmentFundRecord 可迭代对象。

    Returns:
        保留两位小数的净投入金额。
    """
    total = 0.0
    for f in funds:
        if f.record_type == "deposit":
            total += f.amount
        elif f.record_type == "withdraw":
            total -= f.amount
        elif f.record_type == "experience":
            # 正数赠金发放照常计入；负数只在「非失效赠金」时扣减
            if f.amount >= 0 or not is_expired_bonus(f.note):
                total += f.amount
    return round(total, 2)


def _net(t) -> float:
    return (t.pnl or 0) + (t.commission or 0) + (t.overnight_fee or 0)


def _trade_date(t) -> date:
    if t.close_time:
        return t.close_time.date()
    if t.open_time:
        return t.open_time.date()
    return t.trade_date


def _holding_minutes(t) -> int | None:
    if not t.open_time or not t.close_time or t.close_time <= t.open_time:
        return None
    return int(round((t.close_time - t.open_time).total_seconds() / 60))


def build_investment_report(
    db: Session,
    start: date,
    end: date,
    label: str,
    user_id: int | None = None,
):
    """按给定起止区间聚合外汇交易与资金动态，生成投资报告内容。"""
    today = date.today()

    trade_stmt = select(InvestmentForex).where(
        InvestmentForex.trade_date >= start,
        InvestmentForex.trade_date <= end,
    )
    fund_stmt = select(InvestmentFundRecord).where(
        InvestmentFundRecord.record_date >= start,
        InvestmentFundRecord.record_date <= end,
    )
    if user_id is not None:
        trade_stmt = trade_stmt.where(InvestmentForex.user_id == user_id)
        fund_stmt = fund_stmt.where(InvestmentFundRecord.user_id == user_id)
    trades = db.scalars(trade_stmt).all()
    closed = [t for t in trades if t.status == "closed"]
    funds = db.scalars(fund_stmt).all()

    deposit = sum(f.amount for f in funds if f.record_type == "deposit")
    withdraw = sum(f.amount for f in funds if f.record_type == "withdraw")
    experience = sum(f.amount for f in funds if f.record_type == "experience")

    nets = [(_trade_date(t), _net(t), t) for t in closed]
    net_profit = round(sum(n for _, n, _ in nets), 2)
    gross_pnl = round(sum(t.pnl or 0 for t in closed), 2)
    commission = round(sum(t.commission or 0 for t in closed), 2)
    overnight = round(sum(t.overnight_fee or 0 for t in closed), 2)

    wins = [n for _, n, _ in nets if n > 0]
    losses = [n for _, n, _ in nets if n < 0]
    gross_win = sum(wins)
    gross_loss = abs(sum(losses))
    win_rate = round(len(wins) / len(closed) * 100, 1) if closed else None
    pp_ratio = round(gross_win / gross_loss, 2) if gross_loss else None
    avg_win = round(gross_win / len(wins), 2) if wins else None
    avg_loss = round(gross_loss / len(losses), 2) if losses else None

    # 按品种
    by_symbol: dict[str, dict] = {}
    for t in closed:
        s = by_symbol.setdefault(t.symbol, {"count": 0, "win": 0, "pnl": 0.0})
        s["count"] += 1
        s["pnl"] = round(s["pnl"] + _net(t), 2)
        if _net(t) > 0:
            s["win"] += 1
    by_symbol = dict(sorted(by_symbol.items(), key=lambda x: -x[1]["pnl"]))

    # 按日
    daily: dict[str, float] = defaultdict(float)
    for d, n, _ in nets:
        daily[d.isoformat()] = round(daily[d.isoformat()] + n, 2)

    # 多空
    buys = [n for (_, n, t) in nets if t.order_type == "buy"]
    sells = [n for (_, n, t) in nets if t.order_type == "sell"]

    # 盈利/亏损 Top
    sorted_by_net = sorted(nets, key=lambda x: -x[1])
    top_wins = [x for x in sorted_by_net[:5] if x[1] > 0]
    top_losses = sorted([x for x in nets if x[1] < 0], key=lambda x: x[1])[:5]

    # 账户净值口径（业务定义，不是券商账户余额快照）：
    #   净值 = 净投入 + 区间净盈亏
    #   净投入 = 入金 - 出金 + 赠金发放 - 体验金亏损
    # 失效赠金（备注含 bns807）不从本金里剔除，等价于仍计入本金；
    # 赠金只在体验金记录这一处计一次，不再叠加剩余赠金余额。
    # 真实库代入：6033.40 - 3242.76 + 0 - 13.91 + (-2776.73) = 0.00
    account_equity = round(net_capital_of(funds) + net_profit, 2)

    title = f"{label} 投资报告"
    summary = (
        f"统计区间 {start.isoformat()} ~ {end.isoformat()}，共 {len(closed)} 笔平仓交易，"
        f"净收益 {net_profit:+,.2f}，胜率 {win_rate or 0}%，账户净值 {account_equity:,.2f}。"
    )
    content = [
        {"type": "h2", "text": "一、整体概览"},
        {
            "type": "table",
            "header": ["指标", "数值"],
            "rows": [
                ["交易笔数", f"{len(trades)} 笔（持仓 {sum(1 for t in trades if t.status=='open')}）"],
                ["平仓笔数", f"{len(closed)} 笔"],
                ["净收益", f"{net_profit:+,.2f}"],
                ["毛盈亏", f"{gross_pnl:+,.2f}"],
                ["手续费合计", f"{commission:+,.2f}"],
                ["隔夜费合计", f"{overnight:+,.2f}"],
                ["胜率", f"{win_rate or 0}%"],
                ["盈亏比", f"{pp_ratio or 0:g}"],
                ["平均盈利", f"{avg_win or 0:+.2f}"],
                ["平均亏损", f"{avg_loss or 0:+.2f}"],
                ["账户净值", f"{account_equity:,.2f}"],
                ["入金 / 出金", f"{deposit:,.2f} / {withdraw:,.2f}"],
                ["体验金", f"{experience:,.2f}"],
            ],
        },
        {"type": "h2", "text": "二、多空盈亏"},
        {
            "type": "table",
            "header": ["方向", "笔数", "净盈亏"],
            "rows": [
                ["做多 Buy", f"{len(buys)}", f"{round(sum(buys), 2):+,.2f}"],
                ["做空 Sell", f"{len(sells)}", f"{round(sum(sells), 2):+,.2f}"],
            ],
        },
        {"type": "h2", "text": "三、按交易品种"},
        {
            "type": "table",
            "header": ["品种", "笔数", "胜率", "净盈亏"],
            "rows": [
                [
                    s,
                    v["count"],
                    f"{round(v['win'] / v['count'] * 100, 1) if v['count'] else 0}%",
                    f"{v['pnl']:+,.2f}",
                ]
                for s, v in by_symbol.items()
            ]
            or [["—", "0", "—", "—"]],
        },
        {"type": "h2", "text": "四、按日盈亏"},
        {
            "type": "table",
            "header": ["日期", "净盈亏"],
            "rows": [[d, f"{v:+,.2f}"] for d, v in sorted(daily.items())] or [["—", "—"]],
        },
        {"type": "h2", "text": "五、盈利 / 亏损 Top5"},
        {
            "type": "table",
            "header": ["日期", "品种", "方向", "盈亏", "手数"],
            "rows": [
                [d.isoformat(), t.symbol, "多" if t.order_type == "buy" else "空", f"{n:+,.2f}", f"{t.lot_size:g}"]
                for d, n, t in top_wins
            ]
            + [
                [d.isoformat(), t.symbol, "多" if t.order_type == "buy" else "空", f"{n:+,.2f}", f"{t.lot_size:g}"]
                for d, n, t in top_losses
            ]
            or [["—", "—", "—", "—", "—"]],
        },
    ]
    return title, summary, content