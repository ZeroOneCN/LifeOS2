from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.models import FinanceLoanBill, FinanceLoanPlatform, FinanceRepayment
from app.schemas.finance import (
    LoanBillCreate,
    LoanBillRead,
    LoanPlatformCreate,
    LoanPlatformRead,
    RepaymentCreate,
    RepaymentRead,
)

router = APIRouter()


def _platforms_stats(db: Session, days: int) -> dict:
    platforms = db.scalars(select(FinanceLoanPlatform).order_by(FinanceLoanPlatform.id)).all()
    detail = []
    for p in platforms:
        bills = db.scalars(
            select(FinanceLoanBill).where(FinanceLoanBill.platform_id == p.id)
        ).all()
        total_owed = sum(b.amount for b in bills)
        total_paid = sum(b.paid_amount for b in bills)
        detail.append(
            {
                "id": p.id,
                "name": p.name,
                "bill_day": p.bill_day,
                "due_day": p.due_day,
                "credit_limit": p.credit_limit,
                "total_owed": round(total_owed, 2),
                "total_paid": round(total_paid, 2),
                "remaining": round(total_owed - total_paid, 2),
                "bill_count": len(bills),
            }
        )
    detail.sort(key=lambda x: -x["remaining"])
    return {
        "total_remaining": round(sum(d["remaining"] for d in detail), 2),
        "platform_count": len(detail),
        "platforms": detail,
    }


def _bills_stats(db: Session, days: int) -> dict:
    today = date.today()
    rows = db.scalars(select(FinanceLoanBill)).all()
    total = sum(r.amount for r in rows)
    paid = sum(r.paid_amount for r in rows)

    by_month: dict[str, float] = {}
    status_count = {"pending": 0, "partial": 0, "cleared": 0}
    for r in rows:
        key = r.bill_month.isoformat()[:7]
        by_month[key] = by_month.get(key, 0.0) + r.amount
        status_count[r.status] = status_count.get(r.status, 0) + 1

    upcoming = [
        {
            "id": r.id,
            "platform_id": r.platform_id,
            "bill_month": r.bill_month.isoformat(),
            "due_date": r.due_date.isoformat() if r.due_date else None,
            "amount": r.amount,
            "paid_amount": r.paid_amount,
            "remaining": round(r.amount - r.paid_amount, 2),
            "status": r.status,
        }
        for r in rows
        if r.status in ("pending", "partial")
        and r.due_date
        and (r.due_date - today).days <= 30
    ]
    upcoming.sort(key=lambda x: x["due_date"] or "")

    return {
        "total": round(total, 2),
        "paid": round(paid, 2),
        "remaining": round(total - paid, 2),
        "status": status_count,
        "by_month": [
            {"month": m, "amount": round(a, 2)}
            for m, a in sorted(by_month.items(), key=lambda x: x[0], reverse=True)
        ],
        "upcoming": upcoming,
    }


loan_platforms_router = crud_router(
    prefix="/finance/loan-platforms",
    tag="finance-loan-platforms",
    model=FinanceLoanPlatform,
    create_schema=LoanPlatformCreate,
    read_schema=LoanPlatformRead,
    order_by=FinanceLoanPlatform.id,
    stats_func=_platforms_stats,
)
router.include_router(loan_platforms_router)

loan_bills_router = crud_router(
    prefix="/finance/loan-bills",
    tag="finance-loan-bills",
    model=FinanceLoanBill,
    create_schema=LoanBillCreate,
    read_schema=LoanBillRead,
    order_by=FinanceLoanBill.bill_month,
    date_column="bill_month",
    stats_func=_bills_stats,
)
router.include_router(loan_bills_router)


def _sync_bill(db: Session, bill_id: int | None) -> None:
    if not bill_id:
        return
    bill = db.get(FinanceLoanBill, bill_id)
    if not bill:
        return
    reps = db.scalars(
        select(FinanceRepayment).where(FinanceRepayment.bill_id == bill_id)
    ).all()
    bill.paid_amount = sum(r.amount for r in reps)
    if bill.amount - bill.paid_amount <= 1e-6:
        bill.status = "cleared"
    elif bill.paid_amount > 0:
        bill.status = "partial"
    else:
        bill.status = "pending"


repayments_router = APIRouter(prefix="/finance/repayments", tags=["finance-repayments"])


@repayments_router.get("")
def list_repayments(
    bill_id: int | None = None,
    db: Session = Depends(get_db),
):
    stmt = select(FinanceRepayment).order_by(FinanceRepayment.repay_date.desc())
    if bill_id:
        stmt = stmt.where(FinanceRepayment.bill_id == bill_id)
    return db.scalars(stmt).all()


@repayments_router.post("", response_model=RepaymentRead, status_code=201)
def create_repayment(payload: RepaymentCreate, db: Session = Depends(get_db)):
    if not payload.bill_id:
        raise HTTPException(status_code=400, detail="还款必须关联账单")
    bill = db.get(FinanceLoanBill, payload.bill_id)
    if not bill:
        raise HTTPException(status_code=404, detail="账单不存在")
    remaining = bill.amount - bill.paid_amount
    if payload.amount > remaining + 1e-6:
        raise HTTPException(status_code=400, detail=f"还款金额不能超过剩余欠款 {remaining:.2f}")
    obj = FinanceRepayment(**payload.model_dump())
    db.add(obj)
    _sync_bill(db, payload.bill_id)
    db.commit()
    db.refresh(obj)
    return obj


@repayments_router.get("/stats")
def repayment_stats(days: int = Query(30, ge=1, le=365), db: Session = Depends(get_db)):
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(FinanceRepayment).where(FinanceRepayment.repay_date >= since)
    ).all()
    by_month: dict[str, float] = {}
    for r in rows:
        key = r.repay_date.isoformat()[:7]
        by_month[key] = by_month.get(key, 0.0) + r.amount
    return {
        "days": days,
        "total_repaid": round(sum(by_month.values()), 2),
        "count": len(rows),
        "by_month": [
            {"month": m, "amount": round(a, 2)}
            for m, a in sorted(by_month.items(), key=lambda x: x[0], reverse=True)
        ],
    }


@repayments_router.put("/{item_id}", response_model=RepaymentRead)
def update_repayment(item_id: int, payload: RepaymentCreate, db: Session = Depends(get_db)):
    obj = db.get(FinanceRepayment, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="记录不存在")
    if not payload.bill_id:
        raise HTTPException(status_code=400, detail="还款必须关联账单")
    bill = db.get(FinanceLoanBill, payload.bill_id)
    if not bill:
        raise HTTPException(status_code=404, detail="账单不存在")
    others = db.scalars(
        select(FinanceRepayment).where(
            FinanceRepayment.bill_id == obj.bill_id,
            FinanceRepayment.id != item_id,
        )
    ).all()
    other_sum = sum(o.amount for o in others)
    if payload.amount > bill.amount - other_sum + 1e-6:
        raise HTTPException(status_code=400, detail="还款金额不能超过剩余欠款")
    for key, value in payload.model_dump().items():
        setattr(obj, key, value)
    _sync_bill(db, obj.bill_id)
    db.commit()
    db.refresh(obj)
    return obj


@repayments_router.delete("/{item_id}", status_code=204)
def delete_repayment(item_id: int, db: Session = Depends(get_db)):
    obj = db.get(FinanceRepayment, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="记录不存在")
    db.delete(obj)
    _sync_bill(db, obj.bill_id)
    db.commit()
    return None


router.include_router(repayments_router)