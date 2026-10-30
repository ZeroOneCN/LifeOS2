"""手机号卡话费结算服务：整月一次性 / 按天摊销，余额由流水求和派生。

设计要点：
1. 余额不再手工加减，统一为「opening_balance + Σ流水金额」，流水包括充值、扣费与校准；
2. 扣费幂等：每次自动扣费写入唯一 dedup_key（卡片 + 账期 / 卡片 + 日期），重复执行不会二次扣款；
3. 按天摊销：每天扣「月租 / 当月天数」，扣到当月累计等于月租即停止，最后一天补差保证总额精确；
4. 补跑：无论漏跑多少天，都从当月 1 日按目标累计补齐，只补差额部分；
5. 月度汇总：同步维护 `LifestyleCardBill`（每卡每账期一行），供「扣账账单」标签页展示，避免每天一行撑爆列表。
"""

from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    LifestyleCardBill,
    LifestylePhoneCard,
    LifestylePhoneLedger,
)

MONTHLY_MODE = "monthly"
DAILY_MODE = "daily"


# --------------------------------------------------------------------------
# 基础工具
# --------------------------------------------------------------------------
def month_start(day: date) -> date:
    """返回该日期所在自然月的 1 日。"""
    return day.replace(day=1)


def days_in_month(day: date) -> int:
    """返回该日期所在自然月的天数。"""
    nxt = (month_start(day) + timedelta(days=32)).replace(day=1)
    return (nxt - month_start(day)).days


def daily_amounts(fee: float, days: int) -> list[float]:
    """把月租按天摊分：前 days-1 天等额，最后一天补差，保证合计精确等于月租。

    @param fee 月租金额
    @param days 当月天数
    @return 逐日应扣金额列表（长度 = days）
    """
    fee = round(max(fee, 0.0), 2)
    if days <= 0 or fee <= 0:
        return [0.0] * max(days, 0)
    base = round(fee / days, 2)
    amounts = [base] * days
    amounts[-1] = round(fee - base * (days - 1), 2)
    return amounts


def is_chargeable(card: LifestylePhoneCard) -> bool:
    """判断该卡是否适用话费扣费（正常在用 + 按月付费 + 有月租）。"""
    return (
        card.status == "active"
        and card.billing_type == "monthly"
        and (card.monthly_fee or 0) > 0
    )


def daily_rate(card: LifestylePhoneCard, day: date | None = None) -> float:
    """按天模式的单日摊销额（按指定月份天数计算）。"""
    day = day or date.today()
    if not is_chargeable(card) or card.charge_mode != DAILY_MODE:
        return 0.0
    amounts = daily_amounts(card.monthly_fee or 0, days_in_month(day))
    return amounts[-1] if len(amounts) == 1 else amounts[0]


# --------------------------------------------------------------------------
# 余额派生
# --------------------------------------------------------------------------
def compute_balances(
    db: Session, user_id: int, card_ids: list[int] | None = None
) -> dict[int, float]:
    """按流水求和计算各卡余额：opening_balance + Σ金额。

    @param card_ids 限定卡片范围；为 None 时统计该用户全部卡片
    @return {card_id: balance}
    """
    stmt = (
        select(LifestylePhoneCard.id, LifestylePhoneCard.opening_balance)
        .where(LifestylePhoneCard.user_id == user_id)
    )
    if card_ids is not None:
        if not card_ids:
            return {}
        stmt = stmt.where(LifestylePhoneCard.id.in_(card_ids))
    opening: dict[int, float] = {}
    for card_id, opening_balance in db.execute(stmt).all():
        opening[card_id] = opening_balance or 0.0

    sums: dict[int, float] = {}
    if opening:
        stmt2 = (
            select(
                LifestylePhoneLedger.phone_card_id,
                func.coalesce(func.sum(LifestylePhoneLedger.amount), 0),
            )
            .where(
                LifestylePhoneLedger.user_id == user_id,
                LifestylePhoneLedger.phone_card_id.in_(list(opening.keys())),
            )
            .group_by(LifestylePhoneLedger.phone_card_id)
        )
        for card_id, total in db.execute(stmt2).all():
            sums[card_id] = float(total or 0)

    return {
        card_id: round(opening[card_id] + sums.get(card_id, 0.0), 2)
        for card_id in opening
    }


def get_balance(db: Session, card: LifestylePhoneCard) -> float:
    """计算单张卡的当前余额。"""
    return compute_balances(db, card.user_id, [card.id]).get(card.id, 0.0)


def month_charged(db: Session, card: LifestylePhoneCard, period: date) -> float:
    """返回某账期已扣金额（取扣费流水绝对值之和）。"""
    total = db.scalar(
        select(func.coalesce(func.sum(LifestylePhoneLedger.amount), 0)).where(
            LifestylePhoneLedger.user_id == card.user_id,
            LifestylePhoneLedger.phone_card_id == card.id,
            LifestylePhoneLedger.entry_type == "charge",
            LifestylePhoneLedger.period_month == period,
        )
    )
    return round(abs(float(total or 0)), 2)


# --------------------------------------------------------------------------
# 扣费落账
# --------------------------------------------------------------------------
def _add_charge(
    db: Session,
    card: LifestylePhoneCard,
    day: date,
    amount: float,
    period: date,
    dedup_key: str,
    source: str,
    note: str,
) -> bool:
    """写入一条扣费流水（幂等）。返回是否新写入。"""
    if amount <= 0:
        return False
    exists = db.scalar(
        select(LifestylePhoneLedger.id).where(
            LifestylePhoneLedger.dedup_key == dedup_key
        )
    )
    if exists:
        return False
    db.add(
        LifestylePhoneLedger(
            phone_card_id=card.id,
            user_id=card.user_id,
            entry_date=day,
            entry_type="charge",
            amount=-round(amount, 2),
            period_month=period,
            source=source,
            dedup_key=dedup_key,
            note=note,
        )
    )
    # 会话关闭了 autoflush，必须显式 flush，后续汇总查询才能读到本条流水
    db.flush()
    return True


def _sync_bill(
    db: Session, card: LifestylePhoneCard, period: date, mode: str
) -> None:
    """把当月扣费流水汇总写回 `LifestyleCardBill`（每卡每账期一行）。"""
    total = month_charged(db, card, period)
    bill = db.scalar(
        select(LifestyleCardBill).where(
            LifestyleCardBill.user_id == card.user_id,
            LifestyleCardBill.phone_card_id == card.id,
            LifestyleCardBill.bill_month == period,
        )
    )
    note = "按天摊销月租" if mode == DAILY_MODE else "月租扣账"
    if bill is None:
        db.add(
            LifestyleCardBill(
                phone_card_id=card.id,
                user_id=card.user_id,
                bill_month=period,
                amount=total,
                deducted_date=date.today(),
                paid=True,
                note=f"{card.phone_number} {note}",
            )
        )
        db.flush()
    else:
        bill.amount = total
        bill.deducted_date = date.today()
        bill.paid = True
        bill.note = f"{card.phone_number} {note}"


def settle_card(
    db: Session,
    card: LifestylePhoneCard,
    today: date | None = None,
    respect_auto: bool = True,
) -> int:
    """结算单张卡至今天的应扣费用，返回新增扣费笔数。

    @param respect_auto 为 True 时仅处理开启自动扣费的卡（定时任务用）；
                        手动补扣传 False，用户可主动补齐。
    """
    today = today or date.today()
    if not is_chargeable(card):
        return 0
    if respect_auto and not card.auto_charge:
        return 0

    period = month_start(today)
    fee = round(card.monthly_fee or 0, 2)
    added = 0

    if card.charge_mode == DAILY_MODE:
        amounts = daily_amounts(fee, days_in_month(today))
        existing = month_charged(db, card, period)
        for idx in range(today.day):
            day = period + timedelta(days=idx)
            target = round(sum(amounts[: idx + 1]), 2)
            if existing >= target:
                continue
            amount = round(target - existing, 2)
            if _add_charge(
                db,
                card,
                day,
                amount,
                period,
                dedup_key=f"{card.id}:d:{day.isoformat()}",
                source="auto",
                note=f"{card.phone_number} 按天摊销",
            ):
                existing = target
                added += 1
        if added:
            _sync_bill(db, card, period, DAILY_MODE)
    else:
        due_day = min(card.bill_day or 1, days_in_month(today))
        due = period + timedelta(days=due_day - 1)
        if today >= due:
            amount = round(fee - month_charged(db, card, period), 2)
            if amount > 0 and _add_charge(
                db,
                card,
                today,
                amount,
                period,
                dedup_key=f"{card.id}:m:{period.isoformat()}",
                source="auto",
                note=f"{card.phone_number} 月租扣账",
            ):
                _sync_bill(db, card, period, MONTHLY_MODE)
                added += 1

    if added:
        card.balance = get_balance(db, card)
        card.bill_paid_this_month = True
    return added


def settle_user(
    db: Session, user_id: int, today: date | None = None, respect_auto: bool = True
) -> int:
    """结算某用户全部手机卡的应扣费用，返回新增扣费笔数。"""
    cards = db.scalars(
        select(LifestylePhoneCard).where(LifestylePhoneCard.user_id == user_id)
    ).all()
    total = 0
    for card in cards:
        total += settle_card(db, card, today=today, respect_auto=respect_auto)
    return total


def settle_all(db: Session, today: date | None = None) -> dict:
    """结算全库所有手机卡（定时任务调用），返回统计信息。"""
    user_ids = db.scalars(select(LifestylePhoneCard.user_id).distinct()).all()
    charged = 0
    for uid in user_ids:
        charged += settle_user(db, uid, today=today, respect_auto=True)
    return {"users": len(user_ids), "charges": charged}
