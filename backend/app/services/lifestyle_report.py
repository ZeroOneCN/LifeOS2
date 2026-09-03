"""生活报告：按月聚合生活各模块数据生成报告内容，并复用财务报告的 PDF 渲染。"""
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    FinanceShoppingRecord,
    LifestyleBankCard,
    LifestyleCardBill,
    LifestyleItem,
    LifestylePhoneCard,
    LifestyleTodo,
)
from app.services.finance_report import build_pdf  # 复用 PDF 渲染


def _month_range(month: str | None) -> tuple[date, date, str]:
    today = date.today()
    if month:
        try:
            y, m = month.split("-")
            y, m = int(y), int(m)
        except (ValueError, AttributeError):
            y, m = today.year, today.month
    else:
        y, m = today.year, today.month
    import calendar

    start = date(y, m, 1)
    end = date(y, m, calendar.monthrange(y, m)[1])
    return start, end, f"{y}-{m:02d}"


def _usage_days(item: LifestyleItem) -> int:
    """已使用天数：从购买日到使用结束日（或今天）。"""
    purchase = item.purchase_date
    if not purchase:
        return 0
    end = item.end_date or date.today()
    if end < purchase:
        end = purchase
    return max(0, (end - purchase).days)


def build_lifestyle_report(db: Session, month: str | None = None):
    """聚合生活各模块数据生成月度生活报告内容。"""
    start, end, label = _month_range(month)
    today = date.today()

    # ---------- 物品 ----------
    month_items = db.scalars(
        select(LifestyleItem).where(
            LifestyleItem.purchase_date >= start,
            LifestyleItem.purchase_date <= end,
        )
    ).all()
    month_spend = sum(r.price or 0 for r in month_items)
    all_items = db.scalars(select(LifestyleItem)).all()
    total_value = sum(r.price or 0 for r in all_items)
    in_use = sum(1 for r in all_items if r.status == "in_use")
    expiring = sum(
        1
        for r in all_items
        if r.expire_date and r.expire_date >= today and (r.expire_date - today).days <= 30
    )
    expired = sum(1 for r in all_items if r.expire_date and r.expire_date < today)
    # 有效已用物品的最高日均成本
    cost_items = [r for r in all_items if (r.price or 0) > 0 and _usage_days(r) > 0]
    avg_daily_total = sum(r.price / _usage_days(r) for r in cost_items)

    # ---------- 手机卡 ----------
    phones = db.scalars(select(LifestylePhoneCard)).all()
    phone_active = sum(1 for p in phones if p.status == "active")
    monthly_fee_total = sum(p.monthly_fee or 0 for p in phones)
    balance_total = sum(p.balance or 0 for p in phones)

    # 当月扣账
    month_bills = db.scalars(
        select(LifestyleCardBill).where(
            LifestyleCardBill.bill_month >= start,
            LifestyleCardBill.bill_month <= end,
        )
    ).all()
    deduct_total = sum(b.amount for b in month_bills)
    deduct_count = len(month_bills)

    # ---------- 银行卡 ----------
    banks = db.scalars(select(LifestyleBankCard)).all()
    bank_active = sum(1 for b in banks if b.status == "active")
    bank_credit = sum(b.credit_limit or 0 for b in banks if b.card_category == "credit")

    # ---------- 待办 ----------
    todos = db.scalars(select(LifestyleTodo)).all()
    done_todos = sum(1 for t in todos if t.done)
    pending_todos = sum(1 for t in todos if not t.done)
    overdue_todos = sum(
        1 for t in todos if not t.done and t.due_date and t.due_date < today
    )

    title = f"{label} 生活报告"
    summary = (
        f"统计区间 {start.isoformat()} ~ {end.isoformat()}，新增物品 {len(month_items)} 件"
        f"（花费 ¥{month_spend:,.2f}），手机卡扣账 {deduct_count} 笔"
        f"（¥{deduct_total:,.2f}），待办待处理 {pending_todos} 项。"
    )

    content = [
        {"type": "h2", "text": "一、物品概览"},
        {
            "type": "table",
            "header": ["指标", "数值"],
            "rows": [
                ["在册物品总数", f"{len(all_items)} 件"],
                ["使用中", f"{in_use} 件"],
                ["本月新增", f"{len(month_items)} 件（花费 ¥{month_spend:,.2f}）"],
                ["30 天内临期", f"{expiring} 件"],
                ["已过期", f"{expired} 件"],
                ["物品总价值", f"¥{total_value:,.2f}"],
                ["有效物品日均成本合计（≈）", f"¥{avg_daily_total:,.2f}/天"],
            ],
        },
        {"type": "h2", "text": "二、卡片概览"},
        {
            "type": "table",
            "header": ["指标", "数值"],
            "rows": [
                ["手机卡（正常）", f"{phone_active} / {len(phones)} 张"],
                ["手机卡月租合计", f"¥{monthly_fee_total:,.2f}"],
                ["手机卡余额合计", f"¥{balance_total:,.2f}"],
                ["本月扣账", f"{deduct_count} 笔 / ¥{deduct_total:,.2f}"],
                ["银行卡（正常）", f"{bank_active} / {len(banks)} 张"],
                ["信用卡总额度", f"¥{bank_credit:,.2f}"],
            ],
        },
        {"type": "h2", "text": "三、待办清单"},
        {
            "type": "table",
            "header": ["指标", "数值"],
            "rows": [
                ["待办总数", f"{len(todos)} 项"],
                ["已完成", f"{done_todos} 项"],
                ["待处理", f"{pending_todos} 项"],
                ["已逾期", f"{overdue_todos} 项"],
            ],
        },
    ]

    # 当月物品明细（前 30 条）
    if month_items:
        content.append({"type": "h2", "text": "四、本月新增物品"})
        content.append(
            {
                "type": "table",
                "header": ["购买日期", "物品", "分类", "价格", "来源"],
                "rows": [
                    [
                        (r.purchase_date or start).isoformat(),
                        r.item_name,
                        r.category,
                        f"{r.price or 0:g}",
                        "购物同步" if r.source == "shopping" else "手动",
                    ]
                    for r in month_items[:30]
                ],
            }
        )

    return title, summary, content