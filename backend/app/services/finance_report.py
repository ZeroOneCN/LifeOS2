import io
import json
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    FinanceDebt,
    FinanceHousing,
    FinanceInvestment,
    FinanceLoanBill,
    FinanceShoppingRecord,
    FinanceSubscription,
    FinanceTravelDetail,
    FinanceTravelLedger,
    FinanceUtility,
)

# --------------------------------------------------------------------------
# 通用 PDF 渲染：把结构化内容(content JSON)渲染为 A4 PDF
# --------------------------------------------------------------------------
def build_pdf(*, title: str, summary: str, content) -> bytes:
    """把报告内容(JSON section 数组)渲染为 A4 PDF。复用健康报告同款字体/样式。"""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import mm
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    from reportlab.platypus import (
        HRFlowable,
        Paragraph,
        SimpleDocTemplate,
        Spacer,
        Table,
        TableStyle,
    )

    if "STSong-Light" not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
    CJK = "STSong-Light"

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("CJKTitle", parent=styles["Title"], fontName=CJK, fontSize=18, alignment=1)
    subtitle = ParagraphStyle("subtitle", fontName=CJK, fontSize=10, textColor=colors.grey, alignment=1)
    h2 = ParagraphStyle("h2", fontName=CJK, fontSize=13, leading=18, textColor=colors.HexColor("#0f766e"), spaceBefore=10, spaceAfter=4)
    table_hdr = ParagraphStyle("th", fontName=CJK, fontSize=9, textColor=colors.white)
    cell = ParagraphStyle("cell", fontName=CJK, fontSize=9, leading=13)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf,
        pagesize=A4,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        title=title,
    )
    story = []
    story.append(Paragraph(title, title_style))
    if summary:
        story.append(Spacer(1, 3))
        story.append(Paragraph(summary, subtitle))
    story.append(Spacer(1, 4))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#0f766e")))

    if isinstance(content, str):
        try:
            content = json.loads(content or "[]")
        except (ValueError, TypeError):
            content = []

    for i, sec in enumerate(content):
        t = sec.get("type")
        if t == "h2":
            story.append(Paragraph(sec["text"], h2))
            if i:
                story.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#d1d5db")))
        elif t == "paragraph":
            story.append(Paragraph(sec["text"], cell))
            story.append(Spacer(1, 4))
        elif t == "kv":
            if sec.get("label"):
                story.append(Paragraph(sec["label"], h2))
            rows = [[Paragraph(str(k), cell), Paragraph(str(v), cell)] for k, v in sec["rows"]]
            tbl = Table(rows, colWidths=[60 * mm, 118 * mm])
            tbl.setStyle(
                TableStyle(
                    [
                        ("VALIGN", (0, 0), (-1, -1), "TOP"),
                        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e5e7eb")),
                        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f0fdfa")),
                        ("FONTNAME", (0, 0), (-1, -1), CJK),
                    ]
                )
            )
            story.append(tbl)
            story.append(Spacer(1, 5))
        elif t == "table":
            header = sec.get("header") or ["项目", "数值"]
            rows = []
            for r in sec["rows"]:
                if len(r) < 2:
                    r = r + ["-"] * (2 - len(r))
                rows.append([Paragraph(str(c), cell) for c in r])
            data = [[Paragraph(str(h), table_hdr) for h in header]] + rows
            tbl = Table(data, repeatRows=1)
            tbl.setStyle(
                TableStyle(
                    [
                        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0f766e")),
                        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e5e7eb")),
                        ("VALIGN", (0, 0), (-1, -1), "TOP"),
                        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f9fafb")]),
                        ("FONTNAME", (0, 1), (-1, -1), CJK),
                    ]
                )
            )
            story.append(tbl)
            story.append(Spacer(1, 5))

    doc.build(story)
    return buf.getvalue()


# --------------------------------------------------------------------------
# 旅行报告内容构建
# --------------------------------------------------------------------------
def _duration_hours(begin: time | None, end: time | None) -> float:
    if not begin or not end:
        return 0.0
    end_dt = datetime.combine(date.today(), end)
    begin_dt = datetime.combine(date.today(), begin)
    if end <= begin:
        end_dt += timedelta(days=1)
    return round((end_dt - begin_dt).total_seconds() / 3600, 2)


def build_travel_report(db: Session, start: date, end: date, ledger_id: int | None, user_id: int):
    """聚合行程明细生成旅行报告内容。"""
    stmt = select(FinanceTravelDetail).where(
        FinanceTravelDetail.user_id == user_id,
        FinanceTravelDetail.detail_date >= start,
        FinanceTravelDetail.detail_date <= end,
    )
    if ledger_id:
        stmt = stmt.where(FinanceTravelDetail.ledger_id == ledger_id)
    rows = db.scalars(stmt.order_by(FinanceTravelDetail.detail_date)).all()

    ledger_name = "全部行程"
    if ledger_id:
        led = db.get(FinanceTravelLedger, ledger_id)
        if led and led.user_id == user_id:
            ledger_name = led.name

    total_actual = sum(r.actual_price for r in rows)
    total_original = sum(r.original_price for r in rows)
    total_discount = sum(r.discount for r in rows)
    total_hours = round(sum(_duration_hours(r.begin_time, r.end_time) for r in rows), 2)

    by_category: dict[str, dict] = {}
    for r in rows:
        c = by_category.setdefault(r.category, {"actual": 0.0, "count": 0})
        c["actual"] += r.actual_price
        c["count"] += 1
    by_category = dict(sorted(by_category.items(), key=lambda x: -x[1]["actual"]))

    by_date: dict[str, float] = defaultdict(float)
    for r in rows:
        by_date[r.detail_date.isoformat()] += r.actual_price

    title = f"旅行开支报告（{ledger_name}）"
    summary = (
        f"统计区间 {start.isoformat()} ~ {end.isoformat()}，共 {len(rows)} 条明细，"
        f"实付合计 ¥{total_actual:,.2f}，原价 ¥{total_original:,.2f}（优惠 ¥{total_discount:,.2f}），"
        f"记录时长合计 {total_hours} 小时。"
    )
    content = [
        {"type": "h2", "text": "一、总体概览"},
        {
            "type": "kv",
            "label": "关键指标",
            "rows": [
                ["明细笔数", f"{len(rows)} 笔"],
                ["实付合计", f"¥{total_actual:,.2f}"],
                ["原价合计", f"¥{total_original:,.2f}"],
                ["优惠金额", f"¥{total_discount:,.2f}"],
                ["记录时长合计", f"{total_hours} 小时"],
            ],
        },
        {"type": "h2", "text": "二、分类汇总"},
        {
            "type": "table",
            "header": ["分类", "笔数", "实付金额"],
            "rows": [[c, cc["count"], f"¥{cc['actual']:,.2f}"] for c, cc in by_category.items()]
            or [["—", "0", "¥0.00"]],
        },
        {"type": "h2", "text": "三、按日支出"},
        {
            "type": "table",
            "header": ["日期", "实付金额"],
            "rows": [[d, f"¥{a:,.2f}"] for d, a in sorted(by_date.items())] or [["—", "¥0.00"]],
        },
        {"type": "h2", "text": "四、明细列表"},
        {
            "type": "table",
            "header": ["日期", "时间", "分类", "项目", "原价", "优惠", "实付"],
            "rows": [
                [
                    r.detail_date.isoformat(),
                    (f"{r.begin_time:%H:%M}-{r.end_time:%H:%M}" if r.begin_time else "—"),
                    r.category,
                    r.item,
                    f"{r.original_price:g}",
                    f"{r.discount:g}",
                    f"{r.actual_price:g}",
                ]
                for r in rows
            ]
            if rows
            else [["—", "—", "—", "—", "—", "—", "—"]],
        },
    ]
    return title, summary, content


# --------------------------------------------------------------------------
# 财务月度报告内容构建
# --------------------------------------------------------------------------
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


def build_finance_report(db: Session, month: str | None = None, user_id: int | None = None):
    """聚合财务各模块数据生成月度财务报告内容。"""
    start, end, label = _month_range(month)

    # 购物
    shoppings = db.scalars(
        select(FinanceShoppingRecord).where(
            FinanceShoppingRecord.user_id == user_id,
            FinanceShoppingRecord.record_date >= start,
            FinanceShoppingRecord.record_date <= end,
        )
    ).all()
    shopping_total = sum(r.total_price for r in shoppings)

    # 旅行
    travels = db.scalars(
        select(FinanceTravelDetail).where(
            FinanceTravelDetail.user_id == user_id,
            FinanceTravelDetail.detail_date >= start,
            FinanceTravelDetail.detail_date <= end,
        )
    ).all()
    travel_total = sum(r.actual_price for r in travels)

    # 水电
    utils = db.scalars(
        select(FinanceUtility).where(
            FinanceUtility.user_id == user_id,
            FinanceUtility.bill_month >= start,
            FinanceUtility.bill_month <= end,
        )
    ).all()
    utility_total = sum(r.amount for r in utils)

    # 服务订阅（生效中月均）
    subs = db.scalars(
        select(FinanceSubscription).where(
            FinanceSubscription.user_id == user_id,
            FinanceSubscription.status == "active",
        )
    ).all()
    sub_monthly = sum(
        s.amount / {"month": 1, "quarter": 3, "year": 12}.get(s.billing_cycle, 1)
        for s in subs
    )

    # 组合月租（当月）
    houses = db.scalars(
        select(FinanceHousing).where(FinanceHousing.user_id == user_id)
    ).all()
    days_in_month = (end - start).days + 1
    combined_rent = 0.0
    total_deposit = sum(h.deposit or 0 for h in houses)
    for h in houses:
        base = h.actual_monthly_rent / (3 if h.rent_term == "quarterly" else 1)
        hs, he = max(h.move_in_date, start), min(h.move_out_date, end) if h.move_out_date else end
        if hs <= end and he >= start and he > hs:
            combined_rent += base * ((he - hs).days + 1) / days_in_month

    # 网贷（当月账单 + 累计待还）
    loan_bills = db.scalars(
        select(FinanceLoanBill).where(
            FinanceLoanBill.user_id == user_id,
            FinanceLoanBill.bill_month >= start,
            FinanceLoanBill.bill_month <= end,
        )
    ).all()
    loan_month = sum(r.amount for r in loan_bills)
    loan_paid_month = sum(r.paid_amount for r in loan_bills)
    outstanding_loans = sum(
        b.amount - b.paid_amount
        for b in db.scalars(
            select(FinanceLoanBill).where(FinanceLoanBill.user_id == user_id)
        ).all()
        if (b.amount - b.paid_amount) > 0
    )

    # 债务快照
    debts = db.scalars(
        select(FinanceDebt).where(FinanceDebt.user_id == user_id)
    ).all()
    outstanding_debt = sum(
        (r.remaining if r.remaining is not None else r.amount)
        for r in debts
        if r.status == "active"
    )
    borrow_total = sum(r.amount for r in debts if r.direction == "borrow")
    lend_total = sum(r.amount for r in debts if r.direction == "lend")

    # 投资快照
    investments = db.scalars(
        select(FinanceInvestment).where(FinanceInvestment.user_id == user_id)
    ).all()
    invest_pnl = sum(r.pnl for r in investments)

    total_expense = shopping_total + travel_total + utility_total + sub_monthly + combined_rent + loan_paid_month

    # 分类支出占比
    cat_expense = [
        ("购物消费", shopping_total),
        ("旅行开支", travel_total),
        ("水电缴费", utility_total),
        ("服务订阅", sub_monthly),
        ("住房月租", combined_rent),
        ("网贷已还", loan_paid_month),
    ]
    cat_expense = [c for c in cat_expense if c[1] > 0]
    cat_expense.sort(key=lambda x: -x[1])

    title = f"{label} 财务报告"
    summary = (
        f"统计区间 {start.isoformat()} ~ {end.isoformat()}，当月支出合计约 ¥{total_expense:,.2f}；"
        f"购物 {len(shoppings)} 笔、旅行 {len(travels)} 笔，累计网贷待还 ¥{outstanding_loans:,.2f}。"
    )

    content = [
        {"type": "h2", "text": "一、整体概览"},
        {
            "type": "table",
            "header": ["指标", "金额（人民币）"],
            "rows": [
                ["当月支出合计", f"¥{total_expense:,.2f}"],
                ["购物消费", f"¥{shopping_total:,.2f}（{len(shoppings)} 笔）"],
                ["旅行开支", f"¥{travel_total:,.2f}（{len(travels)} 笔）"],
                ["水电缴费", f"¥{utility_total:,.2f}"],
                ["服务订阅（月均）", f"¥{sub_monthly:,.2f}"],
                ["组合房租（当月折算）", f"¥{combined_rent:,.2f}"],
                ["住房押金合计", f"¥{total_deposit:,.2f}"],
                ["网贷当月账单", f"¥{loan_month:,.2f}（已还 ¥{loan_paid_month:,.2f}）"],
            ],
        },
        {"type": "h2", "text": "二、分类支出占比"},
        {
            "type": "table",
            "header": ["类别", "金额", "占比"],
            "rows": [
                [
                    c,
                    f"¥{a:,.2f}",
                    f"{a / total_expense * 100:.1f}%" if total_expense else "—",
                ]
                for c, a in cat_expense
            ]
            if cat_expense
            else [["—", "¥0.00", "—"]],
        },
        {"type": "h2", "text": "三、债务与投资快照"},
        {
            "type": "table",
            "header": ["项目", "金额 / 说明"],
            "rows": [
                ["网贷累计待还", f"¥{outstanding_loans:,.2f}"],
                ["民间借贷未结清", f"¥{outstanding_debt:,.2f}"],
                ["民间借入总额", f"¥{borrow_total:,.2f}"],
                ["民间借出总额", f"¥{lend_total:,.2f}"],
                [
                    "投资平台盈亏合计",
                    f"¥{invest_pnl:,.2f}（{len(investments)} 个平台）",
                ],
            ],
        },
    ]

    # 购物明细（前 30 条）
    if shoppings:
        content.append({"type": "h2", "text": "四、购物明细"})
        content.append(
            {
                "type": "table",
                "header": ["日期", "平台", "商品", "规格", "单价", "总价"],
                "rows": [
                    [
                        r.record_date.isoformat(),
                        str(r.platform_id or "—"),
                        r.product_name,
                        r.spec or "—",
                        f"{r.unit_price or 0:g}",
                        f"{r.total_price:g}",
                    ]
                    for r in shoppings[:30]
                ],
            }
        )

    return title, summary, content