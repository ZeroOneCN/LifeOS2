from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.api.crud import crud_router
from app.models import FinanceDebt, FinanceLoanBill, FinanceLoanPlatform, UserProfile
from app.schemas.finance import (
    DebtCreate,
    DebtRead,
    DebtRepayPayload,
)

router = APIRouter()


def _debt_stats(db: Session, days: int, user_id: int) -> dict:
    """债务统计：方向/状态汇总与逾期情况。"""
    rows = db.scalars(
        select(FinanceDebt).where(FinanceDebt.user_id == user_id)
    ).all()

    total = len(rows)
    borrow_total = sum(r.amount for r in rows if r.direction == "borrow")
    lend_total = sum(r.amount for r in rows if r.direction == "lend")
    outstanding = sum(
        (r.remaining if r.remaining is not None else r.amount)
        for r in rows
        if r.status == "active"
    )
    active = len([r for r in rows if r.status == "active"])
    settled = len([r for r in rows if r.status == "settled"])
    overdue = [
        r
        for r in rows
        if r.status == "active" and r.due_date and r.due_date < date.today()
    ]

    return {
        "total": total,
        "active": active,
        "settled": settled,
        "borrow_total": borrow_total,
        "lend_total": lend_total,
        "outstanding": outstanding,
        "overdue": len(overdue),
        "by_direction": [
            {"direction": "lend", "label": "借出", "amount": lend_total},
            {"direction": "borrow", "label": "借入", "amount": borrow_total},
        ],
        "by_status": [
            {"status": "active", "label": "进行中", "count": active},
            {"status": "settled", "label": "已结清", "count": settled},
        ],
        "overdue_list": [
            {
                "name": r.name,
                "counterparty": r.counterparty,
                "direction": r.direction,
                "remaining": r.remaining if r.remaining is not None else r.amount,
                "due_date": r.due_date,
            }
            for r in sorted(overdue, key=lambda x: x.due_date or date.today())
        ],
    }


@router.get("/finance/debts/loan-sync")
def loan_sync(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
) -> dict:
    """网贷平台的欠款汇总（只读同步，来源为网贷借还模块）。"""
    platforms = db.scalars(
        select(FinanceLoanPlatform)
        .where(FinanceLoanPlatform.user_id == user.id)
        .order_by(FinanceLoanPlatform.id)
    ).all()
    detail = []
    total_remaining = 0.0
    for p in platforms:
        bills = db.scalars(
            select(FinanceLoanBill).where(
                FinanceLoanBill.platform_id == p.id,
                FinanceLoanBill.user_id == user.id,
            )
        ).all()
        remaining = round(sum(b.amount - b.paid_amount for b in bills), 2)
        total_remaining += remaining
        detail.append(
            {
                "platform_id": p.id,
                "name": p.name,
                "remaining": remaining,
                "bill_count": sum(
                    1 for b in bills if b.amount - b.paid_amount > 0
                ),
            }
        )
    detail.sort(key=lambda x: -x["remaining"])
    return {
        "total_remaining": round(total_remaining, 2),
        "platform_count": len(detail),
        "platforms": detail,
    }


@router.post("/finance/debts/{item_id}/repay")
def repay_debt(
    item_id: int,
    payload: DebtRepayPayload,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """债务还款：借入方向还钱减免，借出方向收款冲减；剩余归零自动结清。"""
    debt = db.get(FinanceDebt, item_id)
    if not debt or debt.user_id != user.id:
        raise HTTPException(status_code=404, detail="债务记录不存在")
    if debt.status == "settled":
        raise HTTPException(status_code=400, detail="该债务已结清，无需还款")
    current = debt.remaining if debt.remaining is not None else debt.amount
    if payload.amount > current + 1e-6:
        raise HTTPException(status_code=400, detail=f"还款金额不能超过剩余 {current:.2f}")
    debt.remaining = round(current - payload.amount, 2)
    if debt.remaining <= 1e-6:
        debt.remaining = 0
        debt.status = "settled"
    db.commit()
    return {
        "id": debt.id,
        "name": debt.name,
        "direction": debt.direction,
        "remaining": debt.remaining,
        "status": debt.status,
        "repay": payload.repay_date,
        "amount": round(payload.amount, 2),
    }


router.include_router(
    crud_router(
        prefix="/finance/debts",
        tag="finance-debts",
        model=FinanceDebt,
        create_schema=DebtCreate,
        read_schema=DebtRead,
        order_by=FinanceDebt.debt_date,
        date_column="debt_date",
        stats_func=_debt_stats,
    )
)