# -*- coding: utf-8 -*-
"""健康报告：自动汇总健康中心各模块数据，生成结构化专业报告，并支持 PDF 导出。"""
from __future__ import annotations

import io
import json
from collections import defaultdict
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    HealthBody,
    HealthCheckup,
    HealthDiet,
    HealthFitness,
    HealthMedStock,
    HealthReport,
    HealthSteps,
    HealthVitalsSleep,
)
from app.models.health import HealthMedication

MEAL_LABEL = {
    "breakfast": "早餐",
    "lunch": "午餐",
    "dinner": "晚餐",
    "snack": "加餐",
}

RESULT_LABEL = {"normal": "正常", "high": "偏高", "low": "偏低"}


def _fmt_hours(minutes: int | None) -> str:
    if minutes is None:
        return "-"
    m = int(round(minutes))
    return f"{m // 60} 小时 {m % 60} 分钟"


def _fmt_time(t) -> str:
    return t.strftime("%H:%M") if t else "-"


def _avg(values) -> float | None:
    vals = [v for v in values if v is not None]
    return round(sum(vals) / len(vals), 1) if vals else None


def build_report_data(db: Session, start: date, end: date) -> dict:
    """聚合健康中心各模块在 [start, end] 期间的数据。"""
    # ---- 睡眠与体征 ----
    vitals = db.scalars(
        select(HealthVitalsSleep)
        .where(HealthVitalsSleep.record_date >= start)
        .order_by(HealthVitalsSleep.record_date)
    ).all()
    latest_v = vitals[-1] if vitals else None
    sleep_durs = [v.sleep_duration_min for v in vitals if v.sleep_duration_min]
    qualities = [v.sleep_quality for v in vitals if v.sleep_quality]

    # ---- 健身运动 ----
    fitness = db.scalars(
        select(HealthFitness).where(HealthFitness.record_date >= start)
    ).all()

    # ---- 饮食 ----
    diets = db.scalars(
        select(HealthDiet).where(HealthDiet.record_date >= start)
    ).all()
    diet_by_type: dict[str, int] = defaultdict(int)
    for d in diets:
        diet_by_type[d.meal_type] += 1

    # ---- 体重与体成分 ----
    body = db.scalars(
        select(HealthBody).order_by(HealthBody.record_date)
    ).all()
    body_in = [b for b in body if start <= b.record_date <= end]

    # ---- 步数 ----
    steps = db.scalars(
        select(HealthSteps).where(HealthSteps.record_date >= start)
    ).all()
    step_by_day: dict[date, int] = defaultdict(int)
    for s in steps:
        step_by_day[s.record_date] += s.steps
    step_vals = list(step_by_day.values())

    # ---- 体检 ----
    checkups = db.scalars(
        select(HealthCheckup).where(HealthCheckup.check_date >= start)
    ).all()
    status_counts = {"normal": 0, "high": 0, "low": 0}
    abnormal = []
    for c in checkups:
        st = c.result or "normal"
        if st in status_counts:
            status_counts[st] += 1
        if st != "normal":
            abnormal.append(
                {
                    "check_date": c.check_date.isoformat(),
                    "item_name": c.item_name,
                    "value": c.value,
                    "unit": c.unit,
                    "result": st,
                    "reference_range": c.reference_range,
                }
            )

    # ---- 用药 ----
    meds = db.scalars(
        select(HealthMedication).where(HealthMedication.record_date >= start)
    ).all()
    taken = [m for m in meds if m.taken]
    stocks = db.scalars(select(HealthMedStock)).all()
    low_stock = [
        {
            "medicine_name": s.medicine_name,
            "stock_qty": s.stock_qty,
            "threshold": s.threshold,
            "unit": s.unit,
        }
        for s in stocks
        if s.threshold is not None and s.stock_qty <= s.threshold
    ]

    return {
        "period": {"start": start.isoformat(), "end": end.isoformat()},
        # 睡眠体征
        "latest_vitals": (
            {
                "record_date": latest_v.record_date.isoformat(),
                "blood_pressure_high": latest_v.blood_pressure_high,
                "blood_pressure_low": latest_v.blood_pressure_low,
                "heart_rate": latest_v.heart_rate,
                "blood_oxygen": latest_v.blood_oxygen,
                "blood_glucose": latest_v.blood_glucose,
                "body_temp": latest_v.body_temp,
                "bedtime": _fmt_time(latest_v.bedtime),
                "wake_time": _fmt_time(latest_v.wake_time),
                "sleep_duration_min": latest_v.sleep_duration_min,
                "sleep_quality": latest_v.sleep_quality,
            }
            if latest_v
            else None
        ),
        "avg_sleep_min": _avg(sleep_durs),
        "avg_sleep_quality": _avg(qualities),
        "sleep_records": len(vitals),
        # 运动
        "fitness_count": len(fitness),
        "fitness_minutes": sum(f.duration_min or 0 for f in fitness),
        "fitness_calories": round(sum(f.calories or 0 for f in fitness), 1),
        # 饮食
        "diet_meals": len(diets),
        "diet_by_type": [{"name": MEAL_LABEL.get(k, k), "count": v} for k, v in sorted(diet_by_type.items(), key=lambda x: x[0])],
        "diet_calories": round(sum(d.calories or 0 for d in diets), 1),
        "diet_protein": round(sum(d.protein or 0 for d in diets), 1),
        "diet_carbs": round(sum(d.carbs or 0 for d in diets), 1),
        "diet_fat": round(sum(d.fat or 0 for d in diets), 1),
        # 体重
        "body_records": len(body_in),
        "body_latest": (
            {
                "record_date": body_in[-1].record_date.isoformat(),
                "height_cm": body_in[-1].height_cm,
                "weight_kg": body_in[-1].weight_kg,
                "bmi": body_in[-1].bmi,
                "body_fat_percent": body_in[-1].body_fat_percent,
                "muscle_percent": body_in[-1].muscle_percent,
            }
            if body_in
            else None
        ),
        "body_first": (
            {
                "record_date": body_in[0].record_date.isoformat(),
                "weight_kg": body_in[0].weight_kg,
            }
            if body_in
            else None
        ),
        "weight_change": (
            round((body_in[-1].weight_kg or 0) - (body_in[0].weight_kg or 0), 1)
            if len(body_in) >= 1 and body_in[-1].weight_kg and body_in[0].weight_kg
            else None
        ),
        # 步数
        "steps_total": sum(step_vals),
        "steps_avg_daily": _avg(step_vals),
        "steps_max_daily": max(step_vals) if step_vals else None,
        "steps_days": len(step_by_day),
        # 体检
        "checkup_total": len(checkups),
        "checkup_status": status_counts,
        "checkup_abnormal": abnormal,
        # 用药
        "med_total": len(meds),
        "med_taken": len(taken),
        "med_taken_rate": round(len(taken) / len(meds) * 100) if meds else None,
        "low_stock": low_stock,
    }


def build_content_json(data: dict) -> tuple[str, str, list]:
    """根据聚合数据生成专业报告的标题、摘要与结构化内容(section 列表)。"""
    p = data["period"]
    title = f"健康报告（{p['start']} 至 {p['end']}）"
    sundry: list[str] = []
    if data["latest_vitals"] and data["latest_vitals"]["blood_glucose"]:
        glucose = data["latest_vitals"]["blood_glucose"]
        if glucose > 6.1:
            sundry.append(f"最新空腹血糖 {glucose} mmol/L 略高，建议控制主食摄入并复测")
        elif 3.9 <= glucose <= 6.1:
            sundry.append(f"血糖值 {glucose} mmol/L 处于正常范围")
    if data["body_latest"] and data["body_latest"]["bmi"]:
        bmi = data["body_latest"]["bmi"]
        if bmi < 18.5:
            sundry.append("BMI 偏瘦，建议适当增加营养与力量训练")
        elif bmi > 24:
            sundry.append("BMI 偏高，建议控制热量并加强有氧运动")
        else:
            sundry.append("BMI 处于健康范围，请继续保持")
    if data["checkup_abnormal"]:
        sundry.append(f"本次体检发现 {len(data['checkup_abnormal'])} 项指标异常，请重点关注")
    else:
        sundry.append("体检指标均在参考范围内，状态良好")
    if data["low_stock"]:
        names = "、".join(s["medicine_name"] for s in data["low_stock"])
        sundry.append(f"以下药品库存偏低，请及时补药：{names}")
    summary = "；".join(sundry) if sundry else "本期各健康指标总体稳定，请继续保持良好的作息与运动习惯。"

    content: list = []
    # 1 生命体征与睡眠
    content.append({"type": "h2", "text": "一、生命体征"})
    v = data["latest_vitals"]
    if v:
        content.append(
            {
                "type": "table",
                "name": "最新体征",
                "rows": [
                    ["血压", f"{v['blood_pressure_high'] or '-'}/{v['blood_pressure_low'] or '-'} mmHg"],
                    ["心率", f"{v['heart_rate'] or '-'} 次/分"],
                    ["血氧", f"{v['blood_oxygen'] or '-'} %"],
                    ["血糖", f"{v['blood_glucose'] or '-'} mmol/L"],
                    ["体温", f"{v['body_temp'] or '-'} ℃"],
                    ["睡眠", f"{v['bedtime']} - {v['wake_time']}（{_fmt_hours(v['sleep_duration_min'])}）"],
                    ["睡眠质量", f"{v['sleep_quality'] or '-'}/10"],
                ],
            }
        )
    content.append(
        {
            "type": "kv",
            "rows": [
                ["记录天数", f"{data['sleep_records']} 天"],
                ["平均睡眠时长", _fmt_hours(data["avg_sleep_min"])],
                ["平均睡眠质量", f"{data['avg_sleep_quality'] or '-'}/10"],
            ],
        }
    )
    # 2 身体成分
    content.append({"type": "h2", "text": "二、身体成分"})
    b = data["body_latest"]
    if b:
        content.append(
            {
                "type": "table",
                "name": "最新身体数据",
                "rows": [
                    ["身高", f"{b['height_cm'] or '-'} cm"],
                    ["体重", f"{b['weight_kg'] or '-'} kg"],
                    ["BMI", f"{b['bmi'] or '-'}"],
                    ["体脂率", f"{b['body_fat_percent'] or '-'} %"],
                    ["肌肉率", f"{b['muscle_percent'] or '-'} %"],
                ],
            }
        )
    change = data["weight_change"]
    change_txt = f"期内体重变化 {change:+g} kg" if change is not None else "期内无体重记录"
    content.append({"type": "kv", "rows": [["记录次数", f"{data['body_records']} 次"], ["变化趋势", change_txt]]})
    # 3 运动与步数
    content.append({"type": "h2", "text": "三、运动步数"})
    content.append(
        {
            "type": "kv",
            "rows": [
                ["运动次数", f"{data['fitness_count']} 次"],
                ["运动时长", f"{data['fitness_minutes']} 分钟"],
                ["运动消耗", f"{data['fitness_calories']} 千卡"],
                ["总步数", f"{data['steps_total'] or 0} 步"],
                ["日均步数", f"{data['steps_avg_daily'] or 0} 步"],
                ["单日最高", f"{data['steps_max_daily'] or 0} 步"],
            ],
        }
    )
    # 4 饮食营养
    content.append({"type": "h2", "text": "四、饮食营养"})
    content.append(
        {
            "type": "kv",
            "rows": [
                ["记录餐饮次数", f"{data['diet_meals']} 次"],
                ["总摄入热量", f"{data['diet_calories']} 千卡"],
                ["蛋白质", f"{data['diet_protein']} g"],
                ["碳水", f"{data['diet_carbs']} g"],
                ["脂肪", f"{data['diet_fat']} g"],
            ],
        }
    )
    if data["diet_by_type"]:
        content.append(
            {
                "type": "table",
                "name": "餐饮分布",
                "rows": [[d["name"], f"{d['count']} 次"] for d in data["diet_by_type"]],
            }
        )
    content.append(
        {
            "type": "paragraph",
            "text": f"本期总摄入热量约 {data['diet_calories']} 千卡，运动消耗约 {data['fitness_calories']} 千卡，"
            f"净盈余约 {round(data['diet_calories'] - data['fitness_calories'], 1)} 千卡。",
        }
    )
    # 5 体检
    content.append({"type": "h2", "text": "五、体检指标"})
    content.append(
        {
            "type": "kv",
            "rows": [
                ["检测项数", f"{data['checkup_total']} 项"],
                ["正常", f"{data['checkup_status']['normal']} 项"],
                ["偏高", f"{data['checkup_status']['high']} 项"],
                ["偏低", f"{data['checkup_status']['low']} 项"],
            ],
        }
    )
    if data["checkup_abnormal"]:
        content.append(
            {
                "type": "table",
                "name": "异常指标",
                "rows": [
                    [
                        it["item_name"],
                        f"{it['value'] or '-'} {it['unit'] or ''}",
                        RESULT_LABEL.get(it["result"], it["result"]),
                        it["reference_range"] or "-",
                    ]
                    for it in data["checkup_abnormal"]
                ],
                "header": ["指标", "数值", "状态", "参考范围"],
            }
        )
    # 6 用药
    content.append({"type": "h2", "text": "六、用药管理"})
    med_rows = [
        ["用药记录", f"{data['med_total']} 次"],
    ]
    if data["med_taken_rate"] is not None:
        med_rows.append(["按时服用率", f"{data['med_taken_rate']}%（{data['med_taken']}/{data['med_total']}）"])
    content.append({"type": "kv", "rows": med_rows})
    if data["low_stock"]:
        content.append(
            {
                "type": "kv",
                "label": "低库存提醒",
                "rows": [
                    [
                        s["medicine_name"],
                        f"库存 {s['stock_qty']:g}{s['unit'] or ''}，低于阈值 {s['threshold']:g}{s['unit'] or ''}",
                    ]
                    for s in data["low_stock"]
                ],
            }
        )
    content.append({"type": "paragraph", "text": "结论：" + summary})
    return title, summary, content


def generate_and_save(db: Session, start: date, end: date) -> HealthReport:
    """聚合数据并落库，返回报告记录。"""
    data = build_report_data(db, start, end)
    title, summary, content = build_content_json(data)
    report = HealthReport(
        report_date=end,
        title=title,
        summary=summary,
        content=json.dumps(content, ensure_ascii=False),
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


def get_period(days: int, end: date | None = None) -> tuple[date, date]:
    end = end or date.today()
    start = end - timedelta(days=days - 1)
    return start, end


# --------------------------------------------------------------------------
# PDF 导出
# --------------------------------------------------------------------------
def build_pdf(report: HealthReport) -> bytes:
    """把报告内容(JSON section 数组)渲染为 A4 PDF。"""
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
        title=report.title,
    )
    story = []
    story.append(Paragraph(report.title, title_style))
    if report.summary:
        story.append(Spacer(1, 3))
        story.append(Paragraph(report.summary, subtitle))
    story.append(Spacer(1, 4))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#0f766e")))

    try:
        content = json.loads(report.content or "[]")
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
            rows = [[Paragraph(k, cell), Paragraph(v, cell)] for k, v in sec["rows"]]
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
                rows.append([Paragraph(c, cell) for c in r])
            data = [[Paragraph(h, table_hdr) for h in header]] + rows
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