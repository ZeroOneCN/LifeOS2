import json
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import InvestmentReport, UserProfile
from app.services.finance_report import build_pdf
from app.services.investment_report import build_investment_report

router = APIRouter(prefix="/investment/reports", tags=["investment-reports"])


def _owned_get(db: Session, report_id: int, user_id: int) -> InvestmentReport | None:
    return db.scalar(
        select(InvestmentReport).where(
            InvestmentReport.id == report_id,
            InvestmentReport.user_id == user_id,
        )
    )


def _to_read(r: InvestmentReport) -> dict:
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


def _period_from_month(month: str | None) -> tuple:
    from datetime import date
    import calendar

    today = date.today()
    if month:
        try:
            y, m = month.split("-")
            y, m = int(y), int(m)
        except (ValueError, AttributeError):
            y, m = today.year, today.month
    else:
        y, m = today.year, today.month
    start = date(y, m, 1)
    end = date(y, m, calendar.monthrange(y, m)[1])
    return start, end, f"{y}-{m:02d}"


@router.get("")
def list_reports(db: Session = Depends(get_db),
                 current_user: UserProfile = Depends(get_current_user)):
    rows = db.scalars(
        select(InvestmentReport)
        .where(InvestmentReport.user_id == current_user.id)
        .order_by(InvestmentReport.id.desc())
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


@router.post("/generate")
def generate_report(month: str | None = Query(None, description="YYYY-MM，默认当前月"),
                    db: Session = Depends(get_db),
                    current_user: UserProfile = Depends(get_current_user)):
    start, end, label = _period_from_month(month)
    title, summary, content = build_investment_report(db, month or label, current_user.id)
    report = InvestmentReport(
        user_id=current_user.id,
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
def get_report(report_id: int, db: Session = Depends(get_db),
               current_user: UserProfile = Depends(get_current_user)):
    r = _owned_get(db, report_id, current_user.id)
    if not r:
        raise HTTPException(status_code=404, detail="报告不存在")
    return _to_read(r)


@router.get("/{report_id}/export")
def export_report(report_id: int, db: Session = Depends(get_db),
                  current_user: UserProfile = Depends(get_current_user)):
    r = _owned_get(db, report_id, current_user.id)
    if not r:
        raise HTTPException(status_code=404, detail="报告不存在")
    content = json.loads(r.content or "[]")
    filename = r.title or f"investment-report-{report_id}"
    pdf = build_pdf(title=r.title or "投资报告", summary=r.summary or "", content=content)
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}.pdf"
        },
    )


@router.delete("/{report_id}", status_code=204)
def delete_report(report_id: int, db: Session = Depends(get_db),
                  current_user: UserProfile = Depends(get_current_user)):
    r = _owned_get(db, report_id, current_user.id)
    if not r:
        raise HTTPException(status_code=404, detail="报告不存在")
    db.delete(r)
    db.commit()
    return None