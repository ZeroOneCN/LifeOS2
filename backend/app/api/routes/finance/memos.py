from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceMemo
from app.schemas.finance import MemoCreate, MemoRead


def _memo_stats(db: Session, days: int, user_id: int) -> dict:
    rows = db.scalars(
        select(FinanceMemo).where(FinanceMemo.user_id == user_id)
    ).all()
    return {
        "count": len(rows),
        "recent": [
            {"id": r.id, "title": r.title, "memo_date": r.memo_date}
            for r in sorted(rows, key=lambda x: x.memo_date or x.created_at, reverse=True)[:5]
        ],
    }


router = crud_router(
    prefix="/finance/memos",
    tag="finance-memos",
    model=FinanceMemo,
    create_schema=MemoCreate,
    read_schema=MemoRead,
    order_by=FinanceMemo.id,
    stats_func=_memo_stats,
)