from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.api.crud import crud_router
from app.models import FinanceDebt, FinanceDebtPayment, FinanceLoanBill, FinanceLoanPlatform, UserProfile
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
    """债务还款：借入方向还钱减免，借出方向收款冲减；剩余归零自动结清，并记录还款明细。

    金额语义与「账单管理 · 网贷还款」一致：
        amount   = 实付金额（实际支出/收到的钱）
        discount = 优惠金额（减免、抵扣券）
        本次抵减额度 = amount + discount（优惠同样抵减欠款）
    """
    debt = db.get(FinanceDebt, item_id)
    if not debt or debt.user_id != user.id:
        raise HTTPException(status_code=404, detail="债务记录不存在")
    if debt.status == "settled":
        raise HTTPException(status_code=400, detail="该债务已结清，无需还款")
    discount = round(payload.discount or 0, 2)
    if discount < 0:
        raise HTTPException(status_code=400, detail="优惠金额不能为负")
    actual = round(payload.amount, 2)
    applied = round(actual + discount, 2)  # 本次抵减总额
    current = debt.remaining if debt.remaining is not None else debt.amount
    if applied > current + 1e-6:
        raise HTTPException(
            status_code=400, detail=f"实付 + 优惠不能超过剩余 {current:.2f}"
        )
    debt.remaining = round(current - applied, 2)
    if debt.remaining <= 1e-6:
        debt.remaining = 0
        debt.status = "settled"
    db.add(
        FinanceDebtPayment(
            user_id=user.id,
            debt_id=item_id,
            repay_date=payload.repay_date,
            amount=actual,
            discount=discount,
            note=payload.note,
        )
    )
    db.commit()
    return {
        "id": debt.id,
        "name": debt.name,
        "direction": debt.direction,
        "remaining": debt.remaining,
        "status": debt.status,
        "repay": payload.repay_date,
        "amount": actual,
        "discount": discount,
        "applied": applied,
    }


@router.get("/finance/debts/{item_id}/payments")
def list_debt_payments(
    item_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
) -> list[dict]:
    """查询某笔借贷的还款/收款明细（新在前）。"""
    debt = db.get(FinanceDebt, item_id)
    if not debt or debt.user_id != user.id:
        raise HTTPException(status_code=404, detail="债务记录不存在")
    rows = db.scalars(
        select(FinanceDebtPayment)
        .where(FinanceDebtPayment.debt_id == item_id)
        .order_by(FinanceDebtPayment.repay_date.desc(), FinanceDebtPayment.id.desc())
    ).all()
    return [
        {
            "id": r.id,
            "debt_id": r.debt_id,
            "repay_date": r.repay_date,
            "amount": r.amount,  # 实付
            "discount": r.discount or 0,  # 优惠
            "applied": round((r.amount or 0) + (r.discount or 0), 2),  # 本次抵减总额
            "note": r.note,
        }
        for r in rows
    ]


@router.patch("/finance/debts/{item_id}/payments/{payment_id}")
def update_debt_payment(
    item_id: int,
    payment_id: int,
    payload: DebtRepayPayload,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """修改一笔还款明细：更新日期、金额（实付/优惠）、备注，并重新同步债务剩余金额。

    金额语义与还款一致：本次抵减额度 = amount(实付) + discount(优惠)。
    """
    debt = db.get(FinanceDebt, item_id)
    if not debt or debt.user_id != user.id:
        raise HTTPException(status_code=404, detail="债务记录不存在")
    payment = db.get(FinanceDebtPayment, payment_id)
    if not payment or payment.debt_id != item_id or payment.user_id != user.id:
        raise HTTPException(status_code=404, detail="还款明细不存在")

    # 先回滚旧抵减额，再按新金额重新计算
    old_applied = (payment.amount or 0) + (payment.discount or 0)
    discount = round(payload.discount or 0, 2)
    if discount < 0:
        raise HTTPException(status_code=400, detail="优惠金额不能为负")
    actual = round(payload.amount, 2)
    applied = round(actual + discount, 2)
    current = (debt.remaining if debt.remaining is not None else debt.amount) + old_applied
    if applied > current + 1e-6:
        raise HTTPException(
            status_code=400, detail=f"实付 + 优惠不能超过剩余 {current:.2f}"
        )

    # 更新还款记录
    payment.repay_date = payload.repay_date
    payment.amount = actual
    payment.discount = discount
    payment.note = payload.note

    # 更新债务剩余
    debt.remaining = round(current - applied, 2)
    if debt.remaining <= 1e-6:
        debt.remaining = 0
        debt.status = "settled"
    elif debt.remaining > 1e-6 and debt.status == "settled":
        debt.status = "active"

    db.commit()
    return {
        "id": debt.id,
        "remaining": debt.remaining,
        "status": debt.status,
        "amount": actual,
        "discount": discount,
        "applied": applied,
    }


@router.delete("/finance/debts/{item_id}/payments/{payment_id}")
def delete_debt_payment(
    item_id: int,
    payment_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """删除一笔还款明细，并回滚对应债务的剩余金额（结清则恢复为进行中）。"""
    debt = db.get(FinanceDebt, item_id)
    if not debt or debt.user_id != user.id:
        raise HTTPException(status_code=404, detail="债务记录不存在")
    payment = db.get(FinanceDebtPayment, payment_id)
    if not payment or payment.debt_id != item_id or payment.user_id != user.id:
        raise HTTPException(status_code=404, detail="还款明细不存在")
    rest = (
        (debt.remaining if debt.remaining is not None else debt.amount)
        + (payment.amount or 0)
        + (payment.discount or 0)
    )
    # 回滚不得超过本金总额
    debt.remaining = round(min(rest, debt.amount), 2)
    if debt.remaining > 1e-6 and debt.status == "settled":
        debt.status = "active"
    db.delete(payment)
    db.commit()
    return {"id": debt.id, "remaining": debt.remaining, "status": debt.status}


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