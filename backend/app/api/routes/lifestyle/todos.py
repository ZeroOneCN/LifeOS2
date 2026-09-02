from collections import defaultdict
from datetime import date

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import LifestyleTodo
from app.schemas.lifestyle import TodoCreate, TodoRead

router = APIRouter()


def _todo_stats(db: Session, days: int) -> dict:
    rows = db.scalars(select(LifestyleTodo)).all()

    by_priority = {"high": 0, "medium": 0, "low": 0}
    for r in rows:
        by_priority[r.priority] = by_priority.get(r.priority, 0) + 1

    return {
        "total": len(rows),
        "pending": sum(1 for r in rows if not r.done),
        "done": sum(1 for r in rows if r.done),
        "overdue": sum(
            1
            for r in rows
            if not r.done and r.due_date and r.due_date < date.today()
        ),
        "by_priority": [
            {"priority": k, "count": v} for k, v in by_priority.items()
        ],
    }


router = crud_router(
    prefix="/lifestyle/todos",
    tag="lifestyle-todos",
    model=LifestyleTodo,
    create_schema=TodoCreate,
    read_schema=TodoRead,
    order_by=LifestyleTodo.id,
    stats_func=_todo_stats,
)
