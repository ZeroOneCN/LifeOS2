"""提醒扫描引擎：汇总全系统到期类数据，生成站内通知并下发各渠道。

SCANNERS 注册表：feature_key -> scan(db, advance_days) -> list[dict]
每个 dict 形如 {source_id, title_ctx, content_ctx}，供模板渲染。
"""

from datetime import date, datetime, time as clock_time, timedelta
from typing import Callable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.finance import (
    FinanceDebt,
    FinanceHousing,
    FinanceLoanBill,
    FinanceLoanPlatform,
    FinanceRentTerm,
    FinanceSubscription,
    FinanceUtility,
)
from app.services.med_stock import compute_med_stock_list
from app.models.lifestyle import (
    LifestyleBankCard,
    LifestyleCardBill,
    LifestyleItem,
    LifestylePhoneCard,
    LifestyleTodo,
)
from app.models.health import HealthCheckup
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


# 状态值英文 → 中文映射（用于通知内容展示）
SUB_STATUS_MAP = {
    "active": "生效中",
    "paused": "已暂停",
    "cancelled": "已取消",
    "expired": "已到期",
}
LOAN_STATUS_MAP = {"pending": "待还", "partial": "部分还款", "paid": "已还清"}
# 网贷还款功能开关键：逾期小时提醒任务只处理该模块
LOAN_FEATURE_KEY = "finance_loan_due"
# 药品低库存功能键：库存变化后的实时联动只处理该模块
MED_STOCK_FEATURE_KEY = "health_med_stock"


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
        # 未自动续费且有到期时间：以到期日为最后一次提醒，过期后不再提醒
        if r.end_date and not r.auto_renew:
            if r.end_date < today:
                continue
            if due > r.end_date:
                due = r.end_date
        if not _is_within(due, today, advance):
            continue
        out.append(
            {
                "source_id": r.id,
                "dedup_key": f"{r.id}:{due.isoformat()}",  # 每期续费日不同，按续费日去重
                "title_ctx": {"name": r.name, "due_date": due.isoformat()},
                "content_ctx": {
                    "name": r.name,
                    "category": r.category or "",
                    "due_date": due.isoformat(),
                    "days_left": (due - today).days,
                    "amount": _money(r.amount),
                    "status": SUB_STATUS_MAP.get(r.status, r.status),
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


def _scan_rent(db: Session, advance: int, user_id: int) -> list[dict]:
    """扫描未缴纳的房租期次，到期前按提前天数提醒（含已逾期未缴）。"""
    today = date.today()
    due = today + timedelta(days=advance)
    rows = db.execute(
        select(FinanceRentTerm, FinanceHousing)
        .join(FinanceHousing, FinanceHousing.id == FinanceRentTerm.housing_id)
        .where(
            FinanceRentTerm.user_id == user_id,
            FinanceRentTerm.paid.is_(False),
            FinanceRentTerm.due_date <= due,
            FinanceHousing.user_id == user_id,
        )
        .order_by(FinanceRentTerm.due_date)
    ).all()
    out = []
    for term, housing in rows:
        days_left = (term.due_date - today).days
        if days_left < 0:
            state = f"已逾期 {abs(days_left)} 天"
        elif days_left == 0:
            state = "今日到期"
        else:
            state = f"剩余 {days_left} 天"
        out.append(
            {
                "source_id": term.id,
                # 期次 ID + 到期日去重：调整到期日后可重新提醒
                "dedup_key": f"{term.id}:{term.due_date.isoformat()}",
                "title_ctx": {
                    "housing": housing.short_name or housing.name,
                    "due_date": term.due_date.isoformat(),
                },
                "content_ctx": {
                    "housing": housing.short_name or housing.name,
                    "address": housing.name,
                    "term_no": term.term_no,
                    "amount": _money(term.amount),
                    "due_date": term.due_date.isoformat(),
                    "days_left": days_left,
                    "state": state,
                },
            }
        )
    return out


def _scan_loan(
    db: Session, advance: int, user_id: int, overdue_only: bool = False
) -> list[dict]:
    """扫描网贷账单提醒。

    参数：
        db: 数据库会话。
        advance: 提前提醒天数。
        user_id: 用户 ID。
        overdue_only: 为 True 时只返回已逾期的账单（供每小时提醒任务使用），
            且去重键按“小时”粒度生成，实现每个小时各提醒一次。
    返回值：
        待提醒条目列表，每项含 source_id / title_ctx / content_ctx / 可选 dedup_key。
    """
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
        p.id: p for p in db.scalars(
            select(FinanceLoanPlatform).where(FinanceLoanPlatform.user_id == user_id)
        ).all()
    }
    now = datetime.now()
    out = []
    for r in rows:
        pf = platforms.get(r.platform_id)
        # 容时服务按平台配置：平台勾选「自动生效」（如邮储）或该笔账单已申请容时，才顺延
        grace_days = max(0, pf.grace_days or 0) if pf else 0
        grace_on = bool(grace_days and pf and (pf.grace_auto or r.grace_applied))
        grace_hour = (pf.grace_hour or 0) if pf else 0
        if grace_on:
            # 最终还款日 = 还款日 + 容时天数；截止时刻为当天 grace_hour 点（0 表示当天结束）
            final_due = r.due_date + timedelta(days=grace_days)
            deadline = datetime.combine(
                final_due,
                clock_time(grace_hour, 0) if grace_hour else clock_time(23, 59, 59),
            )
        else:
            final_due = r.due_date
            deadline = datetime.combine(final_due, clock_time(23, 59, 59))
        due_text = final_due.isoformat()
        if grace_on:
            due_text += f" {grace_hour:02d}:00" if grace_hour else ""
            due_text += "（容时）"
        overdue = now > deadline
        # 容时窗口内：已过原还款日、但尚未到最终截止时刻，属于「最后一次机会」
        in_grace = bool(
            grace_on
            and not overdue
            and now > datetime.combine(r.due_date, clock_time(23, 59, 59))
        )
        # 容时提示语：独立段落（前置空行），强调最低还款与不可二次延期
        if overdue:
            grace_tip = (
                "【紧急】已超过最终还款日，不会再次延期。\n"
                "请至少还够最低还款额，否则将上报征信。"
            )
        elif in_grace:
            grace_tip = (
                f"【容时最后机会】已过原还款日，最终截止 {due_text}。\n"
                "请至少还够最低还款额，容时不会二次顺延，超期上报征信。"
            )
        elif grace_on:
            grace_tip = f"可享容时 {grace_days} 天，最终截止 {due_text}，不叠加、不二次延期。"
        else:
            grace_tip = ""
        # 天数文案：逾期时为「已逾期 N 天」，避免出现负数天数
        days_diff = (final_due - today).days
        if overdue:
            days_text = f"已逾期 {(today - final_due).days} 天"
        elif days_diff == 0:
            days_text = "今天到期"
        else:
            days_text = f"剩余 {days_diff} 天"
        if overdue_only:
            # 小时级任务只处理已过最终截止时刻的账单
            if not overdue:
                continue
        elif overdue:
            # 日常扫描跳过逾期账单，由小时级任务专门负责（每天每小时提醒）
            continue
        elif final_due > due:
            # 容时顺延后可能超出提前提醒窗口
            continue
        item = {
            "source_id": r.id,
            "title_ctx": {
                "platform": pf.name if pf else "网贷",
                "due_date": due_text,
            },
            "content_ctx": {
                "platform": pf.name if pf else "网贷",
                "bill_month": r.bill_month.strftime("%Y-%m") if r.bill_month else "",
                "amount": _money(r.amount),
                "due_date": due_text,
                "days_left": days_diff,
                "days_overdue": (today - final_due).days,
                "days_text": days_text,
                "paid_amount": _money(r.paid_amount),
                "status": LOAN_STATUS_MAP.get(r.status, r.status),
                "grace_tip": grace_tip,
                # 容时提示作为独立段落（含前置空行），模板内用 {grace_block} 分隔，视觉不密集
                "grace_block": f"\n\n{grace_tip}" if grace_tip else "",
            },
        }
        if overdue:
            # 逾期：去重键精确到“小时”，确保每个小时各提醒一次
            item["dedup_key"] = f"{r.id}:overdue:{today.isoformat()}:{now.hour}"
        elif in_grace:
            # 容时窗口内：每天一条「最后机会」提醒，到期后由逾期小时任务接管
            item["dedup_key"] = f"{r.id}:grace:{final_due.isoformat()}:{today.isoformat()}"
        elif final_due == today:
            # 到期当天单独去重：与提前提醒(dedup=source_id)区分开，确保当天也会再次提醒；
            # 容时账单带上最终到期日，避免与原还款日的到期提醒互相吞掉
            item["dedup_key"] = f"{r.id}:due:{final_due.isoformat()}" if grace_on else f"{r.id}:due"
        out.append(item)
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
    month_start = today.replace(day=1)
    # 本月已有扣账账单的卡视为已扣账，不重复提醒（存储的 bill_paid_this_month 跨月不会复位）
    paid_ids = set(
        db.scalars(
            select(LifestyleCardBill.phone_card_id).where(
                LifestyleCardBill.user_id == user_id,
                LifestyleCardBill.bill_month >= month_start,
            )
        ).all()
    )
    stmt = select(LifestylePhoneCard).where(
        LifestylePhoneCard.status == "active",
        LifestylePhoneCard.user_id == user_id,
        LifestylePhoneCard.bill_day.isnot(None),
    )
    if paid_ids:
        stmt = stmt.where(LifestylePhoneCard.id.not_in(paid_ids))
    rows = db.scalars(stmt).all()
    out = []
    for r in rows:
        bill_day = _next_day_of_month(today, r.bill_day)
        if not _is_within(bill_day, today, advance):
            continue
        out.append(
            {
                "source_id": r.id,
                "dedup_key": f"{r.id}:{bill_day.isoformat()}",  # 每月账单日不同，按账单日去重
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
                "dedup_key": f"{r.id}:{due.isoformat()}",  # 每月还款日不同，按还款日去重
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


_STOCK_SOURCE_PREFIX = "health_med_stock:"


def _clear_med_stock_notices(db: Session, user_id: int, keep_ids: set[int]) -> None:
    """删除已恢复（库存回到阈值以上）或已删除药品的低库存通知。

    Args:
        db: 数据库会话。
        user_id: 用户 ID。
        keep_ids: 仍需保留提醒的药品库存行 ID 集合。
    """
    rows = db.scalars(
        select(Notification).where(
            Notification.user_id == user_id,
            Notification.source.like(f"{_STOCK_SOURCE_PREFIX}%"),
        )
    ).all()
    for notice in rows:
        try:
            stock_id = int((notice.source or "").split(":")[1])
        except (IndexError, ValueError):
            continue
        if stock_id not in keep_ids:
            db.delete(notice)


def _scan_med_stock(db: Session, _advance: int, user_id: int) -> list[dict]:
    """低库存扫描：每天对每个低于阈值的药品提醒一次，并清理已恢复的旧提醒。"""
    today = date.today()
    stocks = compute_med_stock_list(db, user_id)
    # 补货后库存回到阈值以上时，撤销该药品的历史低库存通知
    _clear_med_stock_notices(
        db, user_id, {r["id"] for r in stocks if r["is_low"]}
    )
    out = []
    for r in stocks:
        if not r["is_low"]:
            continue
        out.append(
            {
                "source_id": r["id"],
                # 按天去重：同一药品每天各提醒一次（旧实现按库存行去重，只提醒一次）
                "dedup_key": f"{r['id']}:{today.isoformat()}",
                "title_ctx": {"medicine_name": r["medicine_name"]},
                "content_ctx": {
                    "medicine_name": r["medicine_name"],
                    "stock": r["stock_qty"],
                    "threshold": r["threshold"],
                },
            }
        )
    return out


def sync_med_stock_reminders(db: Session, user_id: int) -> dict:
    """库存相关数据变化后立即同步低库存提醒（每日提醒 + 实时联动）。

    仅当库存低于药品自身设置的阈值（threshold > 0）时提醒：
    - 低于阈值：若当天尚未提醒过则立即生成站内通知并按配置渠道下发；
    - 补货/调整阈值后不再低于阈值：删除该药品的历史低库存通知。

    Args:
        db: 数据库会话。
        user_id: 用户 ID。

    Returns:
        扫描摘要（结构同 scan_all 的 detail）。
    """
    # 关闭提醒开关时也要清理已恢复的旧通知，因此先独立做一次清理
    stocks = compute_med_stock_list(db, user_id)
    _clear_med_stock_notices(
        db, user_id, {r["id"] for r in stocks if r["is_low"]}
    )
    db.commit()
    return _scan_user(db, user_id, feature_keys={MED_STOCK_FEATURE_KEY})


def _scan_checkup_due(db: Session, advance: int, user_id: int) -> list[dict]:
    """体检到期提醒：基于最近一次体检日期，推算下一次年度体检日。"""
    today = date.today()
    latest = db.scalar(
        select(HealthCheckup.check_date)
        .where(HealthCheckup.user_id == user_id)
        .order_by(HealthCheckup.check_date.desc())
        .limit(1)
    )
    if not latest:
        return []
    next_checkup = _add_months(latest, 12)
    if not _is_within(next_checkup, today, advance):
        return []
    return [
        {
            "source_id": 0,
            "dedup_key": f"checkup:{next_checkup.isoformat()}",
            "title_ctx": {"next_date": next_checkup.isoformat()},
            "content_ctx": {
                "last_date": latest.isoformat(),
                "next_date": next_checkup.isoformat(),
                "days_left": (next_checkup - today).days,
            },
        }
    ]


# 银行卡有效期提醒节奏（按需求固定，不再受功能设置里的提前天数影响）：
#   · 距到期 ≤ 90 天开始提醒，并在最后 15 天之前每月提醒一次（约 90 / 60 / 30 天各一次）
#   · 距到期 ≤ 15 天起每天提醒一次
#   · 已过期且用户未更新有效期时，每天继续提醒
# 实现方式：去重键按「卡片 + 有效期 + 周期桶」生成。周期桶在最后 15 天内按当天日期、
# 之外按月数分桶，从而驱动上述频率；用户一旦更新 expire_date，去重键随之改变，
# 提醒节奏从新的有效期重新计算（即「直到用户更新最新数据」）。
_CARD_EXPIRE_WINDOW = 90  # 提前提醒窗口（天）
_CARD_EXPIRE_DAILY_WITHIN = 15  # 进入每天提醒的剩余天数阈值


def _scan_card_expire(db: Session, advance: int, user_id: int) -> list[dict]:
    """证件到期提醒：银行卡有效期。节奏见上方常量说明。"""
    today = date.today()
    window = max(advance, _CARD_EXPIRE_WINDOW)
    horizon = today + timedelta(days=window)
    rows = db.scalars(
        select(LifestyleBankCard).where(
            LifestyleBankCard.status == "active",
            LifestyleBankCard.user_id == user_id,
            LifestyleBankCard.expire_date.isnot(None),
            # 含已过期卡片：未更新有效期则持续提醒，从窗口内到逾期全覆盖
            LifestyleBankCard.expire_date <= horizon,
        )
    ).all()
    out = []
    for r in rows:
        days_left = (r.expire_date - today).days
        if days_left <= _CARD_EXPIRE_DAILY_WITHIN:
            # 最后 15 天 + 已逾期：每天一次，按当天日期生成周期桶
            bucket = f"d{today.isoformat()}"
        else:
            # 提前 3 个月内：按剩余月数分桶，每月一次（30/60/90 天附近各触发一次）
            bucket = f"m{(days_left + 29) // 30}"
        if days_left < 0:
            state = f"已逾期 {abs(days_left)} 天，数据尚未更新"
        elif days_left == 0:
            state = "今日到期"
        else:
            state = f"剩余 {days_left} 天"
        out.append(
            {
                "source_id": r.id,
                "dedup_key": f"{r.id}:{r.expire_date.isoformat()}:{bucket}",
                "title_ctx": {"card_name": r.card_name, "expire_date": r.expire_date.isoformat()},
                "content_ctx": {
                    "card_name": r.card_name,
                    "bank": r.bank or "",
                    "expire_date": r.expire_date.isoformat(),
                    "days_left": days_left,
                    "state": state,
                },
            }
        )
    return out


SCANNERS: dict[str, Callable[[Session, int, int], list[dict]]] = {
    "finance_subscription_due": _scan_subscription,
    "finance_utility_due": _scan_utility,
    "finance_rent_due": _scan_rent,
    "finance_loan_due": _scan_loan,
    "finance_debt_due": _scan_debt,
    "lifestyle_todo_due": _scan_todo,
    "lifestyle_item_expire": _scan_item_expire,
    "lifestyle_phone_bill": _scan_phone_bill,
    "lifestyle_bankcard_due": _scan_bankcard_due,
    "lifestyle_card_expire": _scan_card_expire,
    "health_med_stock": _scan_med_stock,
    "health_checkup_due": _scan_checkup_due,
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


def _scan_user(
    db: Session,
    user_id: int,
    overdue_only: bool = False,
    feature_keys: set[str] | None = None,
) -> dict:
    """对单个用户执行提醒扫描：按该用户的开关/模板/渠道/数据生成并下发通知。

    参数：
        db: 数据库会话。
        user_id: 用户 ID。
        overdue_only: 为 True 时仅处理网贷逾期账单（供每小时任务调用），
            其余功能模块一律跳过。
        feature_keys: 仅扫描指定功能键集合（用于数据变化后的实时联动）。
    """
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
        # 逾期小时任务只处理网贷账单，其他功能模块跳过
        if overdue_only and s.feature_key != LOAN_FEATURE_KEY:
            continue
        # 实时联动只处理指定功能模块
        if feature_keys and s.feature_key not in feature_keys:
            continue
        try:
            if overdue_only:
                rows = _scan_loan(db, s.advance_days, user_id, overdue_only=True)
            else:
                rows = scanner(db, s.advance_days, user_id)
        except Exception as exc:  # noqa: BLE001
            summary["detail"].append({"feature": s.feature_key, "error": str(exc)})
            continue
        tpl = templates.get(s.feature_key)
        title_tpl = tpl.title_template if tpl else s.name
        content_tpl = tpl.content_template if tpl else "触发提醒：{content}"
        for item in rows:
            summary["scanned"] += 1
            dedup = item.get("dedup_key", item["source_id"])
            source_tag = f"{s.feature_key}:{dedup}"
            # 跨天去重：同一来源（含到期日）已提醒过就不再重复，直到数据变化或删除提醒
            exists = db.scalar(
                select(Notification).where(
                    Notification.source == source_tag,
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


def scan_overdue(db: Session, user_id: int | None = None) -> dict:
    """扫描已逾期的网贷账单，按“小时”去重，实现逾期后每天每小时提醒。

    - user_id 指定时：仅扫描该用户。
    - user_id 为空时：扫描所有用户。
    仅处理启用了「网贷/房贷还款」提醒开关的用户，未开启则不产生任何通知。
    """
    if user_id is not None:
        return _scan_user(db, user_id, overdue_only=True)
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
        _merge_summaries(summary, _scan_user(db, uid, overdue_only=True))
    return summary