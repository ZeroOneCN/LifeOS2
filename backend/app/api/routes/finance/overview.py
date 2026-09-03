from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    FinanceDebt,
    FinanceHousing,
    FinanceInvestment,
    FinanceLoanBill,
    FinancePlan,
    FinanceReminder,
    FinanceShoppingRecord,
    FinanceSubscription,
    FinanceTravelDetail,
    FinanceUtility,
    UserProfile,
)

router = APIRouter(prefix="/finance/overview", tags=["finance-overview"])


@router.get("")
def overview(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
) -> dict:
    today = date.today()
    month_start = today.replace(day=1)
    # 计算当月天数，用于组合房租按天折算
    import calendar

    month_days = calendar.monthrange(today.year, today.month)[1]
    month_end = date(today.year, today.month, month_days)
    week_ago = today - timedelta(days=6)

    # ---------- 本月数据 ----------
    month_shopping = db.scalars(
        select(FinanceShoppingRecord).where(
            FinanceShoppingRecord.user_id == user.id,
            FinanceShoppingRecord.record_date >= month_start,
        )
    ).all()
    month_travel = db.scalars(
        select(FinanceTravelDetail).where(
            FinanceTravelDetail.user_id == user.id,
            FinanceTravelDetail.detail_date >= month_start,
        )
    ).all()
    month_utils = db.scalars(
        select(FinanceUtility).where(
            FinanceUtility.user_id == user.id,
            FinanceUtility.bill_month >= month_start,
        )
    ).all()
    # 生效中的订阅 -> 折算月均
    active_subs = db.scalars(
        select(FinanceSubscription).where(
            FinanceSubscription.user_id == user.id,
            FinanceSubscription.status == "active",
        )
    ).all()
    sub_monthly = sum(
        s.amount / {"month": 1, "quarter": 3, "year": 12}.get(s.billing_cycle, 1)
        for s in active_subs
    )
    # 组合房租（当月折算）
    houses = db.scalars(
        select(FinanceHousing).where(FinanceHousing.user_id == user.id)
    ).all()
    combined_rent = 0.0
    total_deposit = sum(h.deposit or 0 for h in houses)
    for h in houses:
        base = h.actual_monthly_rent / (3 if h.rent_term == "quarterly" else 1)
        hs, he = max(h.move_in_date, month_start), min(h.move_out_date, month_end) if h.move_out_date else month_end
        if hs <= month_end and he >= month_start and he > hs:
            combined_rent += base * ((he - hs).days + 1) / month_days
    month_loans = db.scalars(
        select(FinanceLoanBill).where(
            FinanceLoanBill.user_id == user.id,
            FinanceLoanBill.bill_month >= month_start,
        )
    ).all()

    shopping_total = sum(r.total_price for r in month_shopping)
    travel_total = sum(r.actual_price for r in month_travel)
    utility_total = sum(r.amount for r in month_utils)
    loan_amount = sum(r.amount for r in month_loans)
    loan_paid = sum(r.paid_amount for r in month_loans)

    # ---------- 全量快照 ----------
    all_loans = db.scalars(
        select(FinanceLoanBill).where(FinanceLoanBill.user_id == user.id)
    ).all()
    outstanding_loans = sum(
        (b.amount - b.paid_amount)
        for b in all_loans
        if (b.amount - b.paid_amount) > 0
    )
    debts = db.scalars(
        select(FinanceDebt).where(FinanceDebt.user_id == user.id)
    ).all()
    outstanding_debt = sum(
        (r.remaining if r.remaining is not None else r.amount)
        for r in debts
        if r.status == "active"
    )
    borrow_total = sum(r.amount for r in debts if r.direction == "borrow")
    lend_total = sum(r.amount for r in debts if r.direction == "lend")
    investments = db.scalars(
        select(FinanceInvestment).where(FinanceInvestment.user_id == user.id)
    ).all()
    invest_pnl = sum(r.pnl for r in investments)

    # ---------- 待办 ----------
    pending_bills = db.scalars(
        select(FinanceLoanBill)
        .where(
            FinanceLoanBill.user_id == user.id,
            FinanceLoanBill.status.in_(["pending", "partial"]),
        )
        .order_by(FinanceLoanBill.due_date)
        .limit(5)
    ).all()
    pending_reminders = db.scalars(
        select(FinanceReminder)
        .where(
            FinanceReminder.user_id == user.id,
            FinanceReminder.status == "pending",
        )
        .order_by(FinanceReminder.due_date)
        .limit(5)
    ).all()
    # 待缴水电
    unpaid_utils = db.scalars(
        select(FinanceUtility)
        .where(
            FinanceUtility.user_id == user.id,
            FinanceUtility.paid == False,  # noqa: E712
        )
        .order_by(FinanceUtility.due_date)
        .limit(5)
    ).all()
    # 临近到期的有效订阅
    upcoming_subs = [
        s
        for s in active_subs
        if s.remind_days and 0 <= (expiry_of(s) - today).days <= s.remind_days
    ][:5]
    active_plans = db.scalars(
        select(FinancePlan)
        .where(
            FinancePlan.user_id == user.id,
            FinancePlan.status == "active",
        )
        .order_by(FinancePlan.plan_date.desc())
        .limit(5)
    ).all()

    # ---------- 近 7 天支出趋势 ----------
    week_rows: list[tuple[date, float]] = []
    for r in month_shopping:
        if r.record_date >= week_ago:
            week_rows.append((r.record_date, r.total_price))
    for r in month_travel:
        if r.detail_date >= week_ago:
            week_rows.append((r.detail_date, r.actual_price))
    for r in month_utils:
        if r.bill_month >= week_ago:
            week_rows.append((r.bill_month, r.amount))
    for r in month_loans:
        if r.bill_month >= week_ago and r.bill_month <= today:
            week_rows.append((r.bill_month, r.amount - r.paid_amount))
    daily: dict[date, float] = defaultdict(float)
    for d, amount in week_rows:
        daily[d] += amount

    month_expense = (
        shopping_total
        + travel_total
        + utility_total
        + sub_monthly
        + combined_rent
        + loan_paid
    )

    # 分类支出
    categories = [
        {"label": "购物消费", "amount": round(shopping_total, 2)},
        {"label": "旅行开支", "amount": round(travel_total, 2)},
        {"label": "水电缴费", "amount": round(utility_total, 2)},
        {"label": "服务订阅", "amount": round(sub_monthly, 2)},
        {"label": "住房月租", "amount": round(combined_rent, 2)},
        {"label": "网贷已还", "amount": round(loan_paid, 2)},
    ]
    categories = [c for c in categories if c["amount"] > 0]
    categories.sort(key=lambda c: -c["amount"])

    return {
        "month_expense": round(month_expense, 2),
        "month_purchase_count": len(month_shopping),
        "month_travel_count": len(month_travel),
        "month_bill_count": len(month_loans),
        "utility_count": len(month_utils),
        "sub_count": len(active_subs),
        "unpaid_bills": round(sum(r.amount - r.paid_amount for r in month_loans if r.status in ("pending", "partial")), 2),
        "outstanding_loans": round(outstanding_loans, 2),
        "outstanding_debt": round(outstanding_debt, 2),
        "borrow_total": round(borrow_total, 2),
        "lend_total": round(lend_total, 2),
        "invest_pnl": round(invest_pnl, 2),
        "deposit_total": round(total_deposit, 2),
        "categories": categories,
        "week_trend": [
            {"date": d, "amount": round(amount, 2)}
            for d, amount in sorted(daily.items())
        ],
        "pending_bills": [
            {
                "id": r.id,
                "bill_type": f"网贷账单-{r.bill_month}",
                "amount": r.amount,
                "remaining": round(r.amount - r.paid_amount, 2),
                "due_date": r.due_date,
            }
            for r in pending_bills
        ],
        "pending_utils": [
            {
                "id": r.id,
                "bill_type": f"水电-{r.fee_type}",
                "amount": r.amount,
                "due_date": r.due_date,
            }
            for r in unpaid_utils
        ],
        "pending_reminders": [
            {"id": r.id, "title": r.title, "category": r.category, "amount": r.amount, "due_date": r.due_date}
            for r in pending_reminders
        ],
        "upcoming_subs": [
            {
                "id": s.id,
                "title": s.name,
                "category": s.category,
                "amount": s.amount,
                "due_date": expiry_of(s),
            }
            for s in upcoming_subs
        ],
        "active_plans": [
            {
                "id": r.id,
                "title": r.title,
                "plan_type": r.plan_type,
                "target_amount": r.target_amount,
                "saved_amount": r.saved_amount,
            }
            for r in active_plans
        ],
    }


def expiry_of(s: FinanceSubscription) -> date:
    """根据计费周期估算下一次续费/到期日。"""
    import calendar

    if s.billing_cycle == "year":
        return s.start_date.replace(year=s.start_date.year + 1)
    if s.billing_cycle == "quarter":
        m = s.start_date.month + 3
        y = s.start_date.year + (m - 1) // 12
        m = (m - 1) % 12 + 1
        return date(y, m, min(s.start_date.day, calendar.monthrange(y, m)[1]))
    m = s.start_date.month + 1
    y = s.start_date.year + (m - 1) // 12
    m = (m - 1) % 12 + 1
    return date(y, m, min(s.start_date.day, calendar.monthrange(y, m)[1]))