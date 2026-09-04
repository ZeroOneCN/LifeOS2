from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.api.routes.finance.subscriptions import _next_renewal
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    FinanceLoanBill,
    FinanceReminder,
    FinanceSubscription,
    FinanceUtility,
    UserProfile,
)
from app.models.notification_center import FeatureReminderSetting
from app.schemas.finance import ReminderCreate, ReminderRead

router = APIRouter()


@router.get("/finance/reminders/aggregate")
def aggregate_reminders(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
) -> dict:
    """聚合财务中心各模块的待办提醒，避免遗漏。"""
    today = date.today()
    items = []

    # 服务订阅：即将续费
    subs = db.scalars(
        select(FinanceSubscription).where(
            FinanceSubscription.user_id == user.id,
            FinanceSubscription.status == "active",
        )
    ).all()
    advance = db.scalar(
        select(FeatureReminderSetting.advance_days).where(
            FeatureReminderSetting.user_id == user.id,
            FeatureReminderSetting.feature_key == "finance_subscription_due",
        )
    )
    if advance is None:
        advance = 30
    for s in subs:
        next_renewal = _next_renewal(s.start_date, s.billing_cycle, today)
        if (next_renewal - today).days <= advance:
            items.append(
                {
                    "source": "订阅",
                    "source_label": "服务订阅",
                    "title": f"{s.name} 续费",
                    "amount": s.amount,
                    "due_date": next_renewal.isoformat(),
                    "status": "overdue" if next_renewal < today else "pending",
                }
            )

    # 水电账单：未缴费
    utils = db.scalars(
        select(FinanceUtility).where(
            FinanceUtility.user_id == user.id,
            FinanceUtility.paid.is_(False),
        )
    ).all()
    for u in utils:
        due = u.due_date or u.bill_month.replace(day=1)
        items.append(
            {
                "source": "水电气",
                "source_label": "水电账单",
                "title": f"{u.fee_type}缴费（{u.bill_month.isoformat()}）",
                "amount": u.amount,
                "due_date": due.isoformat(),
                "status": "overdue" if due < today else "pending",
            }
        )

    # 网贷账单：待还（剩余>0）
    bills = db.scalars(
        select(FinanceLoanBill).where(
            FinanceLoanBill.user_id == user.id,
            FinanceLoanBill.status.in_(["pending", "partial"]),
        )
    ).all()
    for b in bills:
        remaining = b.amount - b.paid_amount
        if remaining <= 0:
            continue
        due = b.due_date or b.bill_month.replace(day=1)
        items.append(
            {
                "source": "网贷",
                "source_label": "网贷账单",
                "title": f"网贷还款（{b.bill_month.isoformat()}）",
                "amount": round(remaining, 2),
                "due_date": due.isoformat(),
                "status": "overdue" if due < today else "pending",
            }
        )

    # 手动提醒：待处理
    manuals = db.scalars(
        select(FinanceReminder).where(
            FinanceReminder.user_id == user.id,
            FinanceReminder.status == "pending",
        )
    ).all()
    for m in manuals:
        due = m.due_date or m.reminder_date
        items.append(
            {
                "source": "手动",
                "source_label": "手动提醒",
                "title": m.title,
                "amount": m.amount,
                "due_date": due.isoformat(),
                "status": "overdue" if due < today else "pending",
            }
        )

    items.sort(key=lambda x: x["due_date"])
    return {
        "total": len(items),
        "pending": sum(1 for i in items if i["status"] == "pending"),
        "overdue": sum(1 for i in items if i["status"] == "overdue"),
        "items": items,
    }


def _reminder_stats(db: Session, days: int, user_id: int) -> dict:
    since = days_since(days)
    stmt = select(FinanceReminder).where(FinanceReminder.user_id == user_id)
    if since is not None:
        stmt = stmt.where(FinanceReminder.reminder_date >= since)
    rows = db.scalars(stmt).all()

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


router.include_router(
    crud_router(
    prefix="/finance/reminders",
    tag="finance-reminders",
    model=FinanceReminder,
    create_schema=ReminderCreate,
    read_schema=ReminderRead,
    order_by=FinanceReminder.reminder_date,
    date_column="reminder_date",
    stats_func=_reminder_stats,
)
)
