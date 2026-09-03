from datetime import date, timedelta
from io import BytesIO
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import HealthReport, UserProfile
from app.schemas.health import ReportCreate, ReportRead
from app.services import health_report


def _reports_stats(db: Session, days: int, user_id: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthReport)
        .where(HealthReport.user_id == user_id)
        .where(HealthReport.report_date >= since)
        .order_by(HealthReport.report_date.desc())
    ).all()

    return {
        "recent": [
            {
                "id": r.id,
                "report_date": r.report_date,
                "title": r.title,
                "summary": r.summary,
            }
            for r in rows[:5]
        ],
        "total_count": len(rows),
    }


router = crud_router(
    prefix="/health/reports",
    tag="health-reports",
    model=HealthReport,
    create_schema=ReportCreate,
    read_schema=ReportRead,
    order_by=HealthReport.report_date,
    date_column="report_date",
    stats_func=_reports_stats,
)


class GenerateReq(BaseModel):
    days: int = 30
    end_date: date | None = None


@router.post("/generate")
def generate_report(
    payload: GenerateReq,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """自动汇总健康中心数据生成报告并落库。"""
    try:
        start, end = health_report.get_period(payload.days, payload.end_date)
    except OverflowError:
        raise HTTPException(status_code=400, detail="日期范围超出范围")
    report = health_report.generate_and_save(db, start, end, user.id)
    return {
        "id": report.id,
        "report_date": report.report_date,
        "title": report.title,
        "summary": report.summary,
        "content": report.content,
    }


@router.get("/{report_id}/export")
def export_report(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """导出指定报告为 PDF。"""
    report = db.scalar(
        select(HealthReport).where(
            HealthReport.id == report_id,
            HealthReport.user_id == user.id,
        )
    )
    if not report:
        raise HTTPException(status_code=404, detail="报告不存在")
    try:
        pdf = health_report.build_pdf(report)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"PDF 生成失败：{exc}")
    filename = f"健康报告_{report.report_date.isoformat()}.pdf"
    return StreamingResponse(
        BytesIO(pdf),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}"},
    )