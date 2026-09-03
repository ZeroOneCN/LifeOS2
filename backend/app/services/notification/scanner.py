"""提醒扫描引擎：汇总全系统到期类数据，生成站内通知并下发各渠道。

SCANNERS 注册表：feature_key -> scan(db, advance_days) -> list[dict]
每个 dict 形如 {source_id, title_ctx, content_ctx}，供模板渲染。
"""

from datetime import date, datetime, timedelta
from typing import Callable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.finance import (
    FinanceDebt,
    FinanceLoanBill,
    FinanceLoanPlatform,
    FinanceReminder,
    FinanceSubscription,
    FinanceUtility,
)
from app.models.health import HealthMedStock
from app.models.lifestyle import (
    LifestyleBankCard,
    LifestyleItem,
    LifestylePhoneCard,
    LifestyleTodo,
)
from app.models.notification import Notification
from app.models.notification_center import (
    FeatureReminderSetting,
    NotificationChannel,
    NotificationSendLog,
    NotificationTemplate,
)
from app.models.user import UserProfile

from .channels import send_to_channel
from .templates import render


def _money(value) -> str:
    return f"¥{value:.2f}" if value is not None else "-"


def _add_months(d: date, months: int) -> date:
    y = d.year + (d.month - 1 + months) // 12
    m = (d.month - 1 + months) % 12 + 1
    day = min(d.day, _days_in_month(y, m))
    return date(y, m, day)


def _days_in_month(y: int, m: int) -> int:
    if m == 12:
        return 31
    return (date(y, m + 1, 1) - date(y, m, 1)).days


def _is_within(due: date, today: date, advance: int) -> bool:
    return today <= due <= today + timedelta(days=advance)


def _next_day_of_month(today: date, day: int) -> date:
    """返回从今天起最近的一个指定日（含本月；过期则跳下月）。"""
    d = min(day, _days_in_month(today.year, today.month))
    candidate = date(today.year, today.month, d)
    if candidate >= today:
        return candidate
    if today.month == 12:
        return date(today.year + 1, 1, min(day, 31))
    nm = today.month + 1
    return date(today.year, nm, min(day, _days_in_month(today.year, nm)))


# ---------- 各功能扫描器 ----------

def _scan_subscription(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    rows = db.scalars(
        select(FinanceSubscription).where(
            FinanceSubscription.status == "active",
            FinanceSubscription.user_id == user_id,
        )
    ).all()
    out = []
    for r in rows:
        cycles = {"month": 1, "quarter": 3, "year": 12}.get(r.billing_cycle, 1)
        start = r.start_date or today
        due = _add_months(start, cycles * max(1, ((today - start).days // 28) // cycles))
        while due < today:
            due = _add_months(due, cycles)
        if not _is_within(due, today, advance):
            continue
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"name": r.name, "due_date": due.isoformat()},
                "content_ctx": {
                    "name": r.name,
                    "category": r.category or "",
                    "due_date": due.isoformat(),
                    "days_left": (due - today).days,
                    "amount": _money(r.amount),
                    "status": r.status,
                },
            }
        )
    return out


def _scan_utility(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.scalars(
        select(FinanceUtility).where(
            FinanceUtility.paid.is_(False),
            FinanceUtility.user_id == user_id,
            FinanceUtility.due_date.isnot(None),
            FinanceUtility.due_date <= due,
        )
    ).all()
    out = []
    for r in rows:
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"name": r.fee_type, "due_date": r.due_date.isoformat()},
                "content_ctx": {
                    "name": r.fee_type,
                    "fee_type": r.fee_type,
                    "bill_month": r.bill_month.strftime("%Y-%m"),
                    "amount": _money(r.amount),
                    "due_date": r.due_date.isoformat(),
                },
            }
        )
    return out


def _scan_loan(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.scalars(
        select(FinanceLoanBill).where(
            FinanceLoanBill.status.in_(["pending", "partial"]),
            FinanceLoanBill.user_id == user_id,
            FinanceLoanBill.due_date.isnot(None),
            FinanceLoanBill.due_date <= due,
        )
    ).all()
    platforms = {
        p.id: p.name for p in db.scalars(
            select(FinanceLoanPlatform).where(FinanceLoanPlatform.user_id == user_id)
        ).all()
    }
    out = []
    for r in rows:
        if r.due_date < today:
            continue
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {
                    "platform": platforms.get(r.platform_id, "网贷"),
                    "due_date": r.due_date.isoformat(),
                },
                "content_ctx": {
                    "platform": platforms.get(r.platform_id, "网贷"),
                    "bill_month": r.bill_month.strftime("%Y-%m") if r.bill_month else "",
                    "amount": _money(r.amount),
                    "due_date": r.due_date.isoformat(),
                    "days_left": (r.due_date - today).days,
                    "paid_amount": _money(r.paid_amount),
                    "status": r.status,
                },
            }
        )
    return out


def _scan_reminder(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.scalars(
        select(FinanceReminder).where(
            FinanceReminder.status == "pending",
            FinanceReminder.user_id == user_id,
            FinanceReminder.due_date.isnot(None),
            FinanceReminder.due_date <= due,
            FinanceReminder.due_date >= today,
        )
    ).all()
    out = []
    for r in rows:
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"title": r.title},
                "content_ctx": {
                    "title": r.title,
                    "category": r.category or "",
                    "amount": _money(r.amount),
                    "due_date": r.due_date.isoformat(),
                    "days_left": (r.due_date - today).days,
                },
            }
        )
    return out


def _scan_debt(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.scalars(
        select(FinanceDebt).where(
            FinanceDebt.status == "active",
            FinanceDebt.user_id == user_id,
            FinanceDebt.due_date.isnot(None),
            FinanceDebt.due_date >= today,
            FinanceDebt.due_date <= due,
        )
    ).all()
    dir_map = {"lend": "借出", "borrow": "借入"}
    out = []
    for r in rows:
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"name": r.name, "due_date": r.due_date.isoformat()},
                "content_ctx": {
                    "name": r.name,
                    "direction": dir_map.get(r.direction, r.direction),
                    "counterparty": r.counterparty or "",
                    "amount": _money(r.amount),
                    "remaining": _money(r.remaining),
                    "due_date": r.due_date.isoformat(),
                    "days_left": (r.due_date - today).days,
                },
            }
        )
    return out


def _scan_todo(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.scalars(
        select(LifestyleTodo).where(
            LifestyleTodo.done.is_(False),
            LifestyleTodo.user_id == user_id,
            LifestyleTodo.due_date.isnot(None),
            LifestyleTodo.due_date >= today,
            LifestyleTodo.due_date <= due,
        )
    ).all()
    out = []
    for r in rows:
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"title": r.title},
                "content_ctx": {
                    "title": r.title,
                    "due_date": r.due_date.isoformat(),
                    "days_left": (r.due_date - today).days,
                    "priority": r.priority or "",
                },
            }
        )
    return out


def _scan_item_expire(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.scalars(
        select(LifestyleItem).where(
            LifestyleItem.user_id == user_id,
            LifestyleItem.expire_date.isnot(None),
            LifestyleItem.expire_date >= today,
            LifestyleItem.expire_date <= due,
        )
    ).all()
    out = []
    for r in rows:
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"item_name": r.item_name, "expire_date": r.expire_date.isoformat()},
                "content_ctx": {
                    "item_name": r.item_name,
                    "category": r.category or "",
                    "expire_date": r.expire_date.isoformat(),
                    "days_left": (r.expire_date - today).days,
                },
            }
        )
    return out


def _scan_phone_bill(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    rows = db.scalars(
        select(LifestylePhoneCard).where(
            LifestylePhoneCard.status == "active",
            LifestylePhoneCard.user_id == user_id,
            LifestylePhoneCard.bill_day.isnot(None),
            LifestylePhoneCard.bill_paid_this_month.is_(False),
        )
    ).all()
    out = []
    for r in rows:
        bill_day = _next_day_of_month(today, r.bill_day)
        if not _is_within(bill_day, today, advance):
            continue
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"phone_number": r.phone_number},
                "content_ctx": {
                    "phone_number": r.phone_number,
                    "operator": r.operator or "",
                    "bill_month": bill_day.strftime("%Y-%m"),
                    "amount": _money(r.monthly_fee),
                    "bill_day": r.bill_day,
                },
            }
        )
    return out


def _scan_bankcard_due(db: Session, advance: int, user_id: int) -> list[dict]:
    today = date.today()
    rows = db.scalars(
        select(LifestyleBankCard).where(
            LifestyleBankCard.card_category == "credit",
            LifestyleBankCard.status == "active",
            LifestyleBankCard.user_id == user_id,
            LifestyleBankCard.due_day.isnot(None),
        )
    ).all()
    out = []
    for r in rows:
        due = _next_day_of_month(today, r.due_day)
        if not _is_within(due, today, advance):
            continue
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"card_name": r.card_name, "due_date": due.isoformat()},
                "content_ctx": {
                    "card_name": r.card_name,
                    "bank": r.bank or "",
                    "due_date": due.isoformat(),
                    "days_left": (due - today).days,
                },
            }
        )
    return out


def _scan_med_stock(db: Session, _advance: int, user_id: int) -> list[dict]:
    rows = db.scalars(
        select(HealthMedStock).where(
            HealthMedStock.stock_qty <= HealthMedStock.threshold,
            HealthMedStock.user_id == user_id,
        )
    ).all()
    out = []
    for r in rows:
        out.append(
            {
                "source_id": r.id,
                "title_ctx": {"medicine_name": r.medicine_name},
                "content_ctx": {
                    "medicine_name": r.medicine_name,
                    "stock": r.stock_qty,
                    "threshold": r.threshold,
                },
            }
        )
    return out


SCANNERS: dict[str, Callable[[Session, int, int], list[dict]]] = {
    "finance_subscription_due": _scan_subscription,
    "finance_utility_due": _scan_utility,
    "finance_loan_due": _scan_loan,
    "finance_reminder_due": _scan_reminder,
    "finance_debt_due": _scan_debt,
    "lifestyle_todo_due": _scan_todo,
    "lifestyle_item_expire": _scan_item_expire,
    "lifestyle_phone_bill": _scan_phone_bill,
    "lifestyle_bankcard_due": _scan_bankcard_due,
    "health_med_stock": _scan_med_stock,
}


# ---------- 主扫描逻辑 ----------

def _resolve_channels(db: Session, setting: FeatureReminderSetting, user_id: int) -> list[NotificationChannel]:
    try:
        import json

        ids = json.loads(setting.channels or "[]")
        ids = [int(i) for i in ids]
    except Exception:
        ids = []
    if ids:
        return list(
            db.scalars(
                select(NotificationChannel).where(
                    NotificationChannel.id.in_(ids),
                    NotificationChannel.user_id == user_id,
                )
            )
        )
    return list(
        db.scalars(
            select(NotificationChannel).where(
                NotificationChannel.enabled.is_(True),
                NotificationChannel.user_id == user_id,
            )
        )
    )


def _scan_user(db: Session, user_id: int) -> dict:
    """对单个用户执行提醒扫描：按该用户的开关/模板/渠道/数据生成并下发通知。"""
    today = date.today()
    templates = {
        t.source: t
        for t in db.scalars(
            select(NotificationTemplate).where(NotificationTemplate.user_id == user_id)
        ).all()
    }
    settings_rows = db.scalars(
        select(FeatureReminderSetting).where(
            FeatureReminderSetting.enabled.is_(True),
            FeatureReminderSetting.user_id == user_id,
        )
    ).all()

    summary = {"scanned": 0, "created": 0, "skipped": 0, "sent": 0, "failed": 0, "detail": []}
    for s in settings_rows:
        scanner = SCANNERS.get(s.feature_key)
        if not scanner:
            continue
        try:
            rows = scanner(db, s.advance_days, user_id)
        except Exception as exc:  # noqa: BLE001
            summary["detail"].append({"feature": s.feature_key, "error": str(exc)})
            continue
        tpl = templates.get(s.feature_key)
        title_tpl = tpl.title_template if tpl else s.name
        content_tpl = tpl.content_template if tpl else "触发提醒：{content}"
        for item in rows:
            summary["scanned"] += 1
            source_tag = f"{s.feature_key}:{item['source_id']}"
            exists = db.scalar(
                select(Notification).where(
                    Notification.source == source_tag,
                    Notification.notify_date == today,
                    Notification.user_id == user_id,
                )
            )
            if exists:
                summary["skipped"] += 1
                continue
            title, content = render(title_tpl, content_tpl, {**item["title_ctx"], **item["content_ctx"]})
            note = Notification(
                user_id=user_id,
                title=title,
                content=content,
                category=s.category,
                source=source_tag,
                read=False,
                notify_date=today,
            )
            db.add(note)
            db.flush()

            sent_c, failed_c = 0, 0
            for ch in _resolve_channels(db, s, user_id):
                ok, result = send_to_channel(ch, title, content)
                status = "sent" if ok else "failed"
                if ok:
                    sent_c += 1
                    summary["sent"] += 1
                else:
                    failed_c += 1
                    summary["failed"] += 1
                db.add(
                    NotificationSendLog(
                        user_id=user_id,
                        notification_id=note.id,
                        channel_type=ch.channel_type,
                        channel_id=ch.id,
                        status=status,
                        error=None if ok else result,
                        sent_at=datetime.now(),
                    )
                )
            summary["created"] += 1
            summary["detail"].append(
                {"feature": s.feature_key, "source_id": item["source_id"], "title": title,
                 "sent": sent_c, "failed": failed_c}
            )
    db.commit()
    return summary


def _merge_summaries(target: dict, src: dict) -> None:
    for key in ("scanned", "created", "skipped", "sent", "failed"):
        target[key] += src[key]
    target["detail"].extend(src["detail"])


def scan_all(db: Session, user_id: int | None = None) -> dict:
    """遍历启用中的功能开关，生成站内通知并下发配置渠道。

    - user_id 指定时：仅扫描该用户。
    - user_id 为空时：扫描所有用户（向后兼容）。
    """
    if user_id is not None:
        return _scan_user(db, user_id)
    user_ids = db.scalars(select(UserProfile.id)).all()
    summary = {
        "scanned": 0,
        "created": 0,
        "skipped": 0,
        "sent": 0,
        "failed": 0,
        "detail": [],
    }
    for uid in user_ids:
        _merge_summaries(summary, _scan_user(db, uid))
    return summary