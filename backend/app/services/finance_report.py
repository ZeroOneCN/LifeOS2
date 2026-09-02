import io
import json
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import FinanceTravelDetail, FinanceTravelLedger

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


def build_travel_report(db: Session, start: date, end: date, ledger_id: int | None):
    """聚合行程明细生成旅行报告内容。"""
    stmt = select(FinanceTravelDetail).where(
        FinanceTravelDetail.detail_date >= start,
        FinanceTravelDetail.detail_date <= end,
    )
    if ledger_id:
        stmt = stmt.where(FinanceTravelDetail.ledger_id == ledger_id)
    rows = db.scalars(stmt.order_by(FinanceTravelDetail.detail_date)).all()

    ledger_name = "全部行程"
    if ledger_id:
        led = db.get(FinanceTravelLedger, ledger_id)
        ledger_name = led.name if led else ledger_name

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