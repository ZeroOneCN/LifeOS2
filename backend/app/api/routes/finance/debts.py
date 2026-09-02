from datetime import date

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceDebt
from app.schemas.finance import DebtCreate, DebtRead

router = APIRouter()


def _debt_stats(db: Session, days: int) -> dict:
    """债务统计：方向/状态汇总与逾期情况。"""
    rows = db.scalars(select(FinanceDebt)).all()

    total = len(rows)
    borrow_total = sum(r.amount for r in rows if r.direction == "borrow")
    lend_total = sum(r.amount for r in rows if r.direction == "lend")
    outstanding = sum(
        (r.remaining if r.remaining is not None else r.amount)
        for r in rows
        if r.status == "active"
    )
    settled = len([r for r in rows if r.status == "settled"])
    active = len([r for r in rows if r.status == "active"])
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


router = crud_router(
    prefix="/finance/debts",
    tag="finance-debts",
    model=FinanceDebt,
    create_schema=DebtCreate,
    read_schema=DebtRead,
    order_by=FinanceDebt.debt_date,
    date_column="debt_date",
    stats_func=_debt_stats,
)
