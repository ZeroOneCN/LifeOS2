from collections import defaultdict
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    LifestyleBankCard,
    LifestyleCardBill,
    LifestyleCarrier,
    LifestylePhoneCard,
    LifestylePhoneLedger,
    LifestylePhoneRecharge,
    UserProfile,
)
from app.schemas.lifestyle import (
    BankCardCreate,
    BankCardRead,
    CardBillCreate,
    CardBillRead,
    CarrierCreate,
    CarrierRead,
    PhoneAdjustCreate,
    PhoneCardCreate,
    PhoneCardRead,
    PhoneLedgerRead,
    PhoneRechargeCreate,
)
from app.services.phone_billing import (
    compute_balances,
    daily_rate,
    get_balance,
    month_charged,
    month_start,
    settle_card,
    settle_user,
)

router = APIRouter()


# --------------------------------------------------------------------------
# 手机卡统计与扣账
# --------------------------------------------------------------------------
def _phone_stats(db: Session, days: int, user_id: int) -> dict:
    today = date.today()
    month_start_date = today.replace(day=1)
    rows = db.scalars(
        select(LifestylePhoneCard).where(LifestylePhoneCard.user_id == user_id)
    ).all()
    bills = db.scalars(
        select(LifestyleCardBill).where(
            LifestyleCardBill.bill_month >= month_start_date,
            LifestyleCardBill.user_id == user_id,
        )
    ).all()
    balances = compute_balances(db, user_id)

    by_operator: dict[str, int] = defaultdict(int)
    by_status: dict[str, int] = defaultdict(int)
    by_billing: dict[str, int] = defaultdict(int)
    for r in rows:
        by_operator[r.operator] += 1
        by_status[r.status] += 1
        by_billing[r.billing_type] += 1

    return {
        "total": len(rows),
        "active": sum(1 for r in rows if r.status == "active"),
        "monthly_fee_total": round(sum(r.monthly_fee or 0 for r in rows), 2),
        "balance_total": round(sum(balances.values()), 2),
        "month_deduct": round(sum(b.amount for b in bills), 2),
        "month_deduct_count": len(bills),
        "unpaid_this_month": sum(1 for r in rows if r.id not in {b.phone_card_id for b in bills}),
        "billing_type": [
            {"billing_type": k, "count": v}
            for k, v in sorted(by_billing.items(), key=lambda x: -x[1])
        ],
        "by_operator": [
            {"operator": k, "count": v}
            for k, v in sorted(by_operator.items(), key=lambda x: -x[1])
        ],
        "by_status": [
            {"status": k, "count": v}
            for k, v in sorted(by_status.items(), key=lambda x: -x[1])
        ],
    }


def _phone_list_transform(items: list, db: Session, user_id: int) -> list:
    """为列表补充派生字段：余额、本月已扣/应扣、单日摊销额、本月扣账状态。

    余额统一由流水求和（opening_balance + Σ流水），避免手工加减造成漂移；
    `bill_paid_this_month` 也由当月流水派生，跨月自动回到「未扣账」。
    """
    if not items:
        return items
    period = month_start(date.today())
    ids = [i.id for i in items]
    balances = compute_balances(db, user_id, ids)
    charged_rows = db.execute(
        select(
            LifestylePhoneLedger.phone_card_id,
            func.coalesce(func.sum(LifestylePhoneLedger.amount), 0),
        )
        .where(
            LifestylePhoneLedger.user_id == user_id,
            LifestylePhoneLedger.phone_card_id.in_(ids),
            LifestylePhoneLedger.entry_type == "charge",
            LifestylePhoneLedger.period_month == period,
        )
        .group_by(LifestylePhoneLedger.phone_card_id)
    ).all()
    charged = {cid: round(abs(float(total or 0)), 2) for cid, total in charged_rows}

    for item in items:
        item.balance = balances.get(item.id, 0.0)
        item.month_charged = charged.get(item.id, 0.0)
        item.month_expected = (
            round(item.monthly_fee or 0, 2)
            if item.billing_type == "monthly" and (item.monthly_fee or 0) > 0
            else 0.0
        )
        item.today_charge = daily_rate(item)
        item.bill_paid_this_month = item.month_charged > 0
    return items


def _phone_extra(api_router: APIRouter):
    @api_router.post("/{item_id}/deduct")
    def deduct_monthly(
        item_id: int,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """手动补扣本月：按该卡的扣费方式补齐应扣金额（幂等，重复点击不会多扣）。

        - 整月模式：到账单日后补扣整笔月租；
        - 按天模式：从当月 1 日补齐到今天的摊销差额。
        """
        card = db.scalars(
            select(LifestylePhoneCard).where(
                LifestylePhoneCard.id == item_id,
                LifestylePhoneCard.user_id == user.id,
            )
        ).first()
        if not card:
            raise HTTPException(status_code=404, detail="手机卡不存在")
        settle_card(db, card, respect_auto=False)
        db.commit()
        db.refresh(card)
        return card

    @api_router.post("/settle")
    def settle_current_user(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """进入页面时幂等补齐全部手机卡的本月应扣（错过的天数自动补跑）。"""
        charged = settle_user(db, user.id, respect_auto=True)
        db.commit()
        return {"charges": charged}

    @api_router.post("/{item_id}/recharge")
    def recharge(
        item_id: int,
        payload: PhoneRechargeCreate,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """充值：写入一条充值流水，余额由流水求和自动更新。"""
        card = db.scalars(
            select(LifestylePhoneCard).where(
                LifestylePhoneCard.id == item_id,
                LifestylePhoneCard.user_id == user.id,
            )
        ).first()
        if not card:
            raise HTTPException(status_code=404, detail="手机卡不存在")
        today = payload.recharge_date or date.today()
        db.add(
            LifestylePhoneLedger(
                phone_card_id=item_id,
                user_id=user.id,
                entry_date=today,
                entry_type="recharge",
                amount=round(payload.amount, 2),
                source="manual",
                dedup_key=None,
                note=payload.note or "话费充值",
            )
        )
        db.flush()
        card.balance = get_balance(db, card)
        db.commit()
        db.refresh(card)
        return card

    @api_router.post("/{item_id}/adjust")
    def adjust_balance(
        item_id: int,
        payload: PhoneAdjustCreate,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """余额校准：把账面余额对齐到运营商显示的真实余额（生成一条差额流水）。"""
        card = db.scalars(
            select(LifestylePhoneCard).where(
                LifestylePhoneCard.id == item_id,
                LifestylePhoneCard.user_id == user.id,
            )
        ).first()
        if not card:
            raise HTTPException(status_code=404, detail="手机卡不存在")
        current = get_balance(db, card)
        diff = round(payload.target_balance - current, 2)
        if abs(diff) < 0.005:
            return card
        db.add(
            LifestylePhoneLedger(
                phone_card_id=item_id,
                user_id=user.id,
                entry_date=payload.adjust_date or date.today(),
                entry_type="adjust",
                amount=diff,
                source="manual",
                dedup_key=None,
                note=payload.note or f"余额校准（{current:.2f} → {payload.target_balance:.2f}）",
            )
        )
        db.flush()
        card.balance = get_balance(db, card)
        db.commit()
        db.refresh(card)
        return card

    @api_router.get("/{item_id}/recharges", response_model=list[PhoneLedgerRead])
    def get_recharges(
        item_id: int,
        limit: int = 10,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """获取指定手机号卡的最近充值记录（读流水中的充值条目）。"""
        return db.scalars(
            select(LifestylePhoneLedger).where(
                LifestylePhoneLedger.user_id == user.id,
                LifestylePhoneLedger.phone_card_id == item_id,
                LifestylePhoneLedger.entry_type == "recharge",
            )
            .order_by(LifestylePhoneLedger.entry_date.desc(), LifestylePhoneLedger.id.desc())
            .limit(limit)
        ).all()

    @api_router.get("/{item_id}/ledger", response_model=list[PhoneLedgerRead])
    def get_ledger(
        item_id: int,
        limit: int = 50,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """获取指定手机号卡的最近资金流水（充值 / 扣费 / 校准）。"""
        return db.scalars(
            select(LifestylePhoneLedger).where(
                LifestylePhoneLedger.user_id == user.id,
                LifestylePhoneLedger.phone_card_id == item_id,
            )
            .order_by(LifestylePhoneLedger.entry_date.desc(), LifestylePhoneLedger.id.desc())
            .limit(limit)
        ).all()


phone_router = crud_router(
    prefix="/lifestyle/phone-cards",
    tag="lifestyle-phone-cards",
    model=LifestylePhoneCard,
    create_schema=PhoneCardCreate,
    read_schema=PhoneCardRead,
    order_by=LifestylePhoneCard.open_date,
    order_dir="asc",
    stats_func=_phone_stats,
    list_transform=_phone_list_transform,
    extra_routes=_phone_extra,
)


# --------------------------------------------------------------------------
# 银行卡统计
# --------------------------------------------------------------------------
def _bank_stats(db: Session, days: int, user_id: int) -> dict:
    rows = db.scalars(
        select(LifestyleBankCard).where(LifestyleBankCard.user_id == user_id)
    ).all()

    by_bank: dict[str, int] = defaultdict(int)
    by_category: dict[str, int] = defaultdict(int)
    by_status: dict[str, int] = defaultdict(int)
    balance_total = 0.0
    credit_total = 0.0
    for r in rows:
        by_bank[r.bank] += 1
        by_category[r.card_category] += 1
        by_status[r.status] += 1
        balance_total += r.balance or 0
        if r.card_category == "credit":
            credit_total += r.credit_limit or 0

    return {
        "total": len(rows),
        "active": sum(1 for r in rows if r.status == "active"),
        "balance_total": round(balance_total, 2),
        "credit_total": round(credit_total, 2),
        "by_bank": [{"bank": k, "count": v} for k, v in sorted(by_bank.items(), key=lambda x: -x[1])],
        "by_category": [
            {"card_category": k, "count": v}
            for k, v in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "by_status": [{"status": k, "count": v} for k, v in sorted(by_status.items(), key=lambda x: -x[1])],
    }


bank_router = crud_router(
    prefix="/lifestyle/bank-cards",
    tag="lifestyle-bank-cards",
    model=LifestyleBankCard,
    create_schema=BankCardCreate,
    read_schema=BankCardRead,
    order_by=LifestyleBankCard.id,
    stats_func=_bank_stats,
    # 列表支持全局模糊搜索与按卡类型 / 状态精确筛选
    search_columns=["card_name", "bank", "card_holder", "card_number"],
    filter_columns=["card_category", "status"],
)


# --------------------------------------------------------------------------
# 运营商平台设置
# --------------------------------------------------------------------------
def _carrier_stats(db: Session, days: int, user_id: int) -> dict:
    rows = db.scalars(
        select(LifestyleCarrier).where(LifestyleCarrier.user_id == user_id)
    ).all()
    return {"total": len(rows)}


carrier_router = crud_router(
    prefix="/lifestyle/carriers",
    tag="lifestyle-carriers",
    model=LifestyleCarrier,
    create_schema=CarrierCreate,
    read_schema=CarrierRead,
    order_by=LifestyleCarrier.id,
    stats_func=_carrier_stats,
)


# --------------------------------------------------------------------------
# 扣账账单
# --------------------------------------------------------------------------
def _bill_stats(db: Session, days: int, user_id: int) -> dict:
    # days<=0 表示「全部」，不过滤；否则按当月起始过滤
    stmt = select(LifestyleCardBill).where(LifestyleCardBill.user_id == user_id)
    if days and days > 0:
        stmt = stmt.where(LifestyleCardBill.bill_month >= date.today().replace(day=1))
    bills = db.scalars(stmt).all()
    by_month: dict[str, float] = defaultdict(float)
    for b in bills:
        by_month[b.bill_month.strftime("%Y-%m")] += b.amount
    return {
        "total": len(bills),
        "month_total": round(sum(b.amount for b in bills), 2),
        "by_month": [{"bill_month": k, "amount": round(v, 2)} for k, v in sorted(by_month.items())],
    }


bill_router = crud_router(
    prefix="/lifestyle/card-bills",
    tag="lifestyle-card-bills",
    model=LifestyleCardBill,
    create_schema=CardBillCreate,
    read_schema=CardBillRead,
    order_by=LifestyleCardBill.id,
    date_column="bill_month",
    stats_func=_bill_stats,
)


for sub in (phone_router, bank_router, carrier_router, bill_router):
    router.include_router(sub)