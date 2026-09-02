from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import FinanceReminder
from app.schemas.finance import ReminderCreate, ReminderRead

router = APIRouter()


def _reminder_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(FinanceReminder).where(FinanceReminder.reminder_date >= since)
    ).all()

    pending = [r for r in rows if r.status == "pending"]
    done = [r for r in rows if r.status == "done"]
    overdue = [r for r in pending if r.due_date and r.due_date < date.today()]

    return {
        "total": len(rows),
        "pending": len(pending),
        "done": len(done),
        "overdue": len(overdue),
        "recent": [
            {
                "reminder_date": r.reminder_date,
                "title": r.title,
                "category": r.category,
                "due_date": r.due_date,
                "status": r.status,
            }
            for r in sorted(rows, key=lambda x: x.due_date or x.reminder_date)
        ],
    }


router = crud_router(
    prefix="/finance/reminders",
    tag="finance-reminders",
    model=FinanceReminder,
    create_schema=ReminderCreate,
    read_schema=ReminderRead,
    order_by=FinanceReminder.reminder_date,
    date_column="reminder_date",
    stats_func=_reminder_stats,
)
