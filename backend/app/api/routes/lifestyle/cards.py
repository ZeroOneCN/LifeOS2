from collections import defaultdict
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    LifestyleBankCard,
    LifestyleCardBill,
    LifestyleCarrier,
    LifestylePhoneCard,
    UserProfile,
)
from app.schemas.lifestyle import (
    BankCardCreate,
    BankCardRead,
    CardBillCreate,
    CardBillRead,
    CarrierCreate,
    CarrierRead,
    PhoneCardCreate,
    PhoneCardRead,
)

router = APIRouter()


# --------------------------------------------------------------------------
# 手机卡统计与扣账
# --------------------------------------------------------------------------
def _phone_stats(db: Session, days: int, user_id: int) -> dict:
    today = date.today()
    month_start = today.replace(day=1)
    rows = db.scalars(
        select(LifestylePhoneCard).where(LifestylePhoneCard.user_id == user_id)
    ).all()
    bills = db.scalars(
        select(LifestyleCardBill).where(
            LifestyleCardBill.bill_month >= month_start,
            LifestyleCardBill.user_id == user_id,
        )
    ).all()

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
        "balance_total": round(sum(r.balance or 0 for r in rows), 2),
        "month_deduct": round(sum(b.amount for b in bills), 2),
        "month_deduct_count": len(bills),
        "unpaid_this_month": sum(1 for r in rows if not r.bill_paid_this_month),
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


def _phone_extra(api_router: APIRouter):
    @api_router.post("/{item_id}/deduct")
    def deduct_monthly(
        item_id: int,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """记录一次当月扣账：生成一条扣账账单流水，并标记本月已扣账。"""
        card = db.scalars(
            select(LifestylePhoneCard).where(
                LifestylePhoneCard.id == item_id,
                LifestylePhoneCard.user_id == user.id,
            )
        ).first()
        if not card:
            raise HTTPException(status_code=404, detail="手机卡不存在")
        fee = card.monthly_fee or 0
        today = date.today()
        bill_month = today.replace(day=1)
        exists = db.scalar(
            select(LifestyleCardBill).where(
                LifestyleCardBill.user_id == user.id,
                LifestyleCardBill.phone_card_id == item_id,
                LifestyleCardBill.bill_month == bill_month,
            )
        )
        if not exists:
            db.add(
                LifestyleCardBill(
                    phone_card_id=item_id,
                    user_id=user.id,
                    bill_month=bill_month,
                    amount=fee,
                    deducted_date=today,
                    paid=True,
                    note=f"{card.phone_number} 月租自动扣账",
                )
            )
        card.bill_paid_this_month = True
        db.commit()
        db.refresh(card)
        return card


phone_router = crud_router(
    prefix="/lifestyle/phone-cards",
    tag="lifestyle-phone-cards",
    model=LifestylePhoneCard,
    create_schema=PhoneCardCreate,
    read_schema=PhoneCardRead,
    order_by=LifestylePhoneCard.id,
    stats_func=_phone_stats,
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
    since = date.today().replace(day=1)
    bills = db.scalars(
        select(LifestyleCardBill).where(
            LifestyleCardBill.bill_month >= since,
            LifestyleCardBill.user_id == user_id,
        )
    ).all()
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