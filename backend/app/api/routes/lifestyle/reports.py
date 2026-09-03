import json
from datetime import date
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import LifestyleLifeReport, UserProfile
from app.services.finance_report import build_pdf
from app.services.lifestyle_report import build_lifestyle_report
from app.services.report_period import resolve_period

router = APIRouter(prefix="/lifestyle/reports", tags=["lifestyle-reports"])


def _to_read(r: LifestyleLifeReport) -> dict:
    content = []
    try:
        content = json.loads(r.content or "[]")
    except (ValueError, TypeError):
        content = []
    return {
        "id": r.id,
        "title": r.title,
        "period_label": r.period_label,
        "period_start": r.period_start.isoformat(),
        "period_end": r.period_end.isoformat(),
        "summary": r.summary,
        "created_at": r.created_at.isoformat() if r.created_at else None,
        "content": content,
    }


@router.get("")
def list_reports(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    rows = db.scalars(
        select(LifestyleLifeReport)
        .where(LifestyleLifeReport.user_id == user.id)
        .order_by(LifestyleLifeReport.id.desc())
    ).all()
    return [
        {
            "id": r.id,
            "title": r.title,
            "period_label": r.period_label,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]


class GenerateReq(BaseModel):
    days: int = 30
    start_date: date | None = None
    end_date: date | None = None


@router.post("/generate")
def generate_report(
    payload: GenerateReq,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    start, end, label = resolve_period(payload.days, payload.start_date, payload.end_date)
    title, summary, content = build_lifestyle_report(db, start, end, label, user.id)
    report = LifestyleLifeReport(
        user_id=user.id,
        title=title,
        period_label=label,
        period_start=start,
        period_end=end,
        summary=summary,
        content=json.dumps(content, ensure_ascii=False),
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return _to_read(report)


@router.get("/{report_id}")
def get_report(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    r = db.scalars(
        select(LifestyleLifeReport).where(
            LifestyleLifeReport.id == report_id,
            LifestyleLifeReport.user_id == user.id,
        )
    ).first()
    if not r:
        raise HTTPException(status_code=404, detail="报告不存在")
    return _to_read(r)


@router.get("/{report_id}/export")
def export_report(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    r = db.scalars(
        select(LifestyleLifeReport).where(
            LifestyleLifeReport.id == report_id,
            LifestyleLifeReport.user_id == user.id,
        )
    ).first()
    if not r:
        raise HTTPException(status_code=404, detail="报告不存在")
    content = json.loads(r.content or "[]")
    filename = r.title or f"life-report-{report_id}"
    pdf = build_pdf(title=r.title or "生活报告", summary=r.summary or "", content=content)
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}.pdf"
        },
    )


@router.delete("/{report_id}", status_code=204)
def delete_report(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    r = db.scalars(
        select(LifestyleLifeReport).where(
            LifestyleLifeReport.id == report_id,
            LifestyleLifeReport.user_id == user.id,
        )
    ).first()
    if not r:
        raise HTTPException(status_code=404, detail="报告不存在")
    db.delete(r)
    db.commit()
    return None