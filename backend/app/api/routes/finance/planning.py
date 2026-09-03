from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.models import FinancePlan
from app.schemas.finance import PlanCreate, PlanRead

router = APIRouter()


def _plan_stats(db: Session, days: int, user_id: int) -> dict:
    since = days_since(days)
    stmt = select(FinancePlan).where(FinancePlan.user_id == user_id)
    if since is not None:
        stmt = stmt.where(FinancePlan.plan_date >= since)
    rows = db.scalars(stmt).all()

    active = [r for r in rows if r.status == "active"]
    done = [r for r in rows if r.status == "done"]

    return {
        "total": len(rows),
        "active": len(active),
        "done": len(done),
        "target_total": round(sum(r.target_amount or 0 for r in rows), 2),
        "saved_total": round(sum(r.saved_amount or 0 for r in rows), 2),
        "by_type": [
            {
                "plan_type": t,
                "count": sum(1 for r in rows if r.plan_type == t),
                "amount": round(
                    sum(r.saved_amount or 0 for r in rows if r.plan_type == t), 2
                ),
            }
            for t in sorted({r.plan_type for r in rows})
        ],
    }


router = crud_router(
    prefix="/finance/planning",
    tag="finance-planning",
    model=FinancePlan,
    create_schema=PlanCreate,
    read_schema=PlanRead,
    order_by=FinancePlan.plan_date,
    date_column="plan_date",
    stats_func=_plan_stats,
)
