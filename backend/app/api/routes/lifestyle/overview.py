from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import (
    LifestyleBankCard,
    LifestyleCardBill,
    LifestyleItem,
    LifestyleLifeReport,
    LifestylePhoneCard,
    LifestyleTodo,
)

router = APIRouter(prefix="/lifestyle/overview", tags=["lifestyle-overview"])


def _usage_days(item: LifestyleItem) -> int:
    purchase = item.purchase_date
    if not purchase:
        return 0
    end = item.end_date or date.today()
    if end < purchase:
        end = purchase
    return max(0, (end - purchase).days)


@router.get("")
def overview(db: Session = Depends(get_db)) -> dict:
    today = date.today()
    month_start = today.replace(day=1)

    # ---------- 物品 ----------
    items = db.scalars(select(LifestyleItem)).all()
    in_use_items = [r for r in items if r.status == "in_use"]
    total_value = sum(r.price or 0 for r in items)
    expiring = [
        r
        for r in items
        if r.expire_date and 0 <= (r.expire_date - today).days <= 30
    ]
    expired_count = sum(1 for r in items if r.expire_date and r.expire_date < today)
    cost_items = [r for r in in_use_items if (r.price or 0) > 0 and _usage_days(r) > 0]
    avg_daily_cost = (
        round(sum(r.price / _usage_days(r) for r in cost_items) / len(cost_items), 2)
        if cost_items
        else 0
    )

    # ---------- 卡片 ----------
    phones = db.scalars(select(LifestylePhoneCard)).all()
    banks = db.scalars(select(LifestyleBankCard)).all()
    month_bills = db.scalars(
        select(LifestyleCardBill).where(LifestyleCardBill.bill_month >= month_start)
    ).all()
    month_deduct = sum(b.amount for b in month_bills)
    unpaid_this_month = sum(1 for p in phones if not p.bill_paid_this_month)

    # ---------- 待办 ----------
    todos = db.scalars(select(LifestyleTodo)).all()
    pending = [t for t in todos if not t.done]
    overdue = [t for t in pending if t.due_date and t.due_date < today]

    latest_report = None
    rep = db.scalars(
        select(LifestyleLifeReport)
        .order_by(LifestyleLifeReport.id.desc())
        .limit(1)
    ).first()
    if rep:
        latest_report = {
            "id": rep.id,
            "title": rep.title,
            "period_label": rep.period_label,
            "summary": rep.summary,
        }

    return {
        "item_total": len(items),
        "item_in_use": len(in_use_items),
        "item_value": round(total_value, 2),
        "item_avg_daily_cost": avg_daily_cost,
        "item_expiring": len(expiring),
        "item_expired": expired_count,
        "phone_total": len(phones),
        "phone_active": sum(1 for p in phones if p.status == "active"),
        "phone_monthly_fee": round(sum(p.monthly_fee or 0 for p in phones), 2),
        "phone_unpaid": unpaid_this_month,
        "bank_total": len(banks),
        "bank_active": sum(1 for b in banks if b.status == "active"),
        "month_deduct": round(month_deduct, 2),
        "month_deduct_count": len(month_bills),
        "todo_total": len(todos),
        "todo_pending": len(pending),
        "todo_overdue": len(overdue),
        "expiring_items": [
            {
                "id": r.id,
                "item_name": r.item_name,
                "category": r.category,
                "expire_date": r.expire_date.isoformat() if r.expire_date else None,
                "days_left": (r.expire_date - today).days,
            }
            for r in sorted(expiring, key=lambda x: x.expire_date or date.max)[:10]
        ],
        "pending_todos": [
            {
                "id": t.id,
                "title": t.title,
                "category": t.category,
                "due_date": t.due_date.isoformat() if t.due_date else None,
                "priority": t.priority,
            }
            for t in pending[:10]
        ],
        "latest_report": latest_report,
    }