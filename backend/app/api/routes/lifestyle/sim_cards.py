from collections import defaultdict

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import LifestyleSimCard
from app.schemas.lifestyle import SimCardCreate, SimCardRead

router = APIRouter()


def _sim_stats(db: Session, days: int) -> dict:
    rows = db.scalars(select(LifestyleSimCard)).all()

    by_type: dict[str, int] = defaultdict(int)
    by_status: dict[str, int] = defaultdict(int)
    for r in rows:
        by_type[r.card_type] += 1
        by_status[r.status] += 1

    return {
        "total": len(rows),
        "balance_total": round(sum(r.balance or 0 for r in rows), 2),
        "by_type": [
            {"card_type": t, "count": n}
            for t, n in sorted(by_type.items(), key=lambda x: -x[1])
        ],
        "by_status": [
            {"status": s, "count": n}
            for s, n in sorted(by_status.items(), key=lambda x: -x[1])
        ],
    }


router = crud_router(
    prefix="/lifestyle/sim-cards",
    tag="lifestyle-sim-cards",
    model=LifestyleSimCard,
    create_schema=SimCardCreate,
    read_schema=SimCardRead,
    order_by=LifestyleSimCard.id,
    stats_func=_sim_stats,
)
