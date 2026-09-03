from collections import defaultdict
from datetime import date, time, timedelta
from urllib.parse import quote

import json

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    FinanceTravelDetail,
    FinanceTravelLedger,
    FinanceTravelReport,
    UserProfile,
)
from app.schemas.health import PageOut
from app.schemas.finance import TravelDetailCreate, TravelDetailRead, TravelLedgerCreate, TravelLedgerRead
from app.services import finance_report

# 行程账本：标准 CRUD
ledgers_router = crud_router(
    prefix="/finance/travel/ledgers",
    tag="finance-travel-ledgers",
    model=FinanceTravelLedger,
    create_schema=TravelLedgerCreate,
    read_schema=TravelLedgerRead,
    order_by=FinanceTravelLedger.id,
)

# 行程明细：自定义路由（账本过滤 + 自动实付 + 统计）
details_router = APIRouter(prefix="/finance/travel/details", tags=["finance-travel"])


def _compute_actual(payload: TravelDetailCreate) -> dict:
    data = payload.model_dump()
    data["actual_price"] = round(data["original_price"] - data["discount"], 2)
    return data


@details_router.get("", response_model=PageOut[TravelDetailRead])
def list_details(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    start: date | None = None,
    end: date | None = None,
    ledger_id: int | None = None,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    stmt = select(FinanceTravelDetail).where(FinanceTravelDetail.user_id == user.id)
    if start:
        stmt = stmt.where(FinanceTravelDetail.detail_date >= start)
    if end:
        stmt = stmt.where(FinanceTravelDetail.detail_date <= end)
    if ledger_id:
        stmt = stmt.where(FinanceTravelDetail.ledger_id == ledger_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(
        stmt.order_by(FinanceTravelDetail.detail_date.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return PageOut(items=rows, total=total, page=page, page_size=page_size)


@details_router.get("/stats")
def details_stats(
    days: int = Query(90, ge=1, le=3650),
    ledger_id: int | None = None,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
) -> dict:
    since = date.today() - timedelta(days=days - 1)
    stmt = select(FinanceTravelDetail).where(
        FinanceTravelDetail.user_id == user.id,
        FinanceTravelDetail.detail_date >= since,
    )
    if ledger_id:
        stmt = stmt.where(FinanceTravelDetail.ledger_id == ledger_id)
    rows = db.scalars(stmt).all()

    total_actual = sum(r.actual_price for r in rows)
    total_original = sum(r.original_price for r in rows)
    total_discount = sum(r.discount for r in rows)

    by_category: defaultdict[str, float] = defaultdict(float)
    monthly: defaultdict[str, float] = defaultdict(float)
    for r in rows:
        by_category[r.category] += r.actual_price
        monthly[r.detail_date.strftime("%Y-%m")] += r.actual_price

    return {
        "total_actual": round(total_actual, 2),
        "total_original": round(total_original, 2),
        "total_discount": round(total_discount, 2),
        "count": len(rows),
        "by_category": [
            {"category": c, "amount": round(a, 2)}
            for c, a in sorted(by_category.items(), key=lambda x: -x[1])
        ],
        "monthly_trend": [
            {"month": m, "amount": round(a, 2)} for m, a in sorted(monthly.items())
        ],
    }


@details_router.post("", response_model=TravelDetailRead, status_code=201)
def create_detail(
    payload: TravelDetailCreate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    data = _compute_actual(payload)
    data["user_id"] = user.id
    obj = FinanceTravelDetail(**data)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@details_router.put("/{item_id}", response_model=TravelDetailRead)
def update_detail(
    item_id: int,
    payload: TravelDetailCreate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    obj = db.get(FinanceTravelDetail, item_id)
    if not obj or obj.user_id != user.id:
        raise HTTPException(status_code=404, detail="记录不存在")
    for key, value in _compute_actual(payload).items():
        setattr(obj, key, value)
    db.commit()
    db.refresh(obj)
    return obj


@details_router.delete("/{item_id}", status_code=204)
def delete_detail(
    item_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    obj = db.get(FinanceTravelDetail, item_id)
    if not obj or obj.user_id != user.id:
        raise HTTPException(status_code=404, detail="记录不存在")
    db.delete(obj)
    db.commit()
    return None


# 旅行报告
report_router = APIRouter(prefix="/finance/travel", tags=["finance-travel"])


class ReportGenReq(BaseModel):
    ledger_id: int | None = None
    days: int = 30
    end_date: date | None = None


def _resolve_period(days: int, end_date: date | None) -> tuple[date, date]:
    end = end_date or date.today()
    start = end - timedelta(days=days - 1)
    return start, end


def _to_read(r: FinanceTravelReport) -> dict:
    content = []
    try:
        content = json.loads(r.content or "[]")
    except (ValueError, TypeError):
        content = []
    return {
        "id": r.id,
        "title": r.title,
        "ledger_id": r.ledger_id,
        "period_start": r.period_start.isoformat() if r.period_start else None,
        "period_end": r.period_end.isoformat() if r.period_end else None,
        "summary": r.summary,
        "created_at": r.created_at.isoformat() if r.created_at else None,
        "content": content,
    }


@report_router.get("/report")
def travel_report_list(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    rows = db.scalars(
        select(FinanceTravelReport)
        .where(FinanceTravelReport.user_id == user.id)
        .order_by(FinanceTravelReport.id.desc())
        .limit(50)
    ).all()
    return [
        {
            "id": r.id,
            "title": r.title,
            "ledger_id": r.ledger_id,
            "period_start": r.period_start.isoformat() if r.period_start else None,
            "period_end": r.period_end.isoformat() if r.period_end else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]


@report_router.post("/report/generate")
def travel_report_generate(
    payload: ReportGenReq,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    start, end = _resolve_period(payload.days, payload.end_date)
    title, summary, content = finance_report.build_travel_report(db, start, end, payload.ledger_id, user.id)
    report = FinanceTravelReport(
        title=title,
        ledger_id=payload.ledger_id,
        period_start=start,
        period_end=end,
        summary=summary,
        content=json.dumps(content, ensure_ascii=False),
        user_id=user.id,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return _to_read(report)


@report_router.get("/report/{report_id}")
def travel_report_get(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    r = db.get(FinanceTravelReport, report_id)
    if not r or r.user_id != user.id:
        raise HTTPException(status_code=404, detail="报告不存在")
    return _to_read(r)


@report_router.get("/report/{report_id}/export")
def travel_report_export(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    r = db.get(FinanceTravelReport, report_id)
    if not r or r.user_id != user.id:
        raise HTTPException(status_code=404, detail="报告不存在")
    content = json.loads(r.content or "[]")
    pdf = finance_report.build_pdf(title=r.title or "旅行开支报告", summary=r.summary or "", content=content)
    filename = (
        f"旅行开支报告_{r.period_start.isoformat()}_{r.period_end.isoformat()}"
        if r.period_start and r.period_end
        else f"旅行开支报告_{report_id}"
    )
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}.pdf"},
    )


@report_router.delete("/report/{report_id}", status_code=204)
def travel_report_delete(
    report_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    r = db.get(FinanceTravelReport, report_id)
    if not r or r.user_id != user.id:
        raise HTTPException(status_code=404, detail="报告不存在")
    db.delete(r)
    db.commit()
    return None


# 合并为一个 router 供 __init__ 使用
router = APIRouter()
router.include_router(ledgers_router)
router.include_router(details_router)
router.include_router(report_router)