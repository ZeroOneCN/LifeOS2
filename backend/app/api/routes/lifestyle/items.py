from collections import defaultdict

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import LifestyleItem
from app.schemas.lifestyle import ItemCreate, ItemRead

router = APIRouter()


def _item_stats(db: Session, days: int) -> dict:
    rows = db.scalars(select(LifestyleItem)).all()

    by_category: dict[str, int] = defaultdict(int)
    by_status: dict[str, int] = defaultdict(int)
    for r in rows:
        by_category[r.category] += 1
        by_status[r.status] += 1

    return {
        "total": len(rows),
        "by_category": [
            {"category": c, "count": n}
            for c, n in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "by_status": [
            {"status": s, "count": n}
            for s, n in sorted(by_status.items(), key=lambda x: -x[1])
        ],
    }


router = crud_router(
    prefix="/lifestyle/items",
    tag="lifestyle-items",
    model=LifestyleItem,
    create_schema=ItemCreate,
    read_schema=ItemRead,
    order_by=LifestyleItem.id,
    stats_func=_item_stats,
)
