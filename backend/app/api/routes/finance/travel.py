from collections import defaultdict
from datetime import date, time, timedelta
from io import BytesIO
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.models import FinanceTravelDetail, FinanceTravelLedger
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
):
    stmt = select(FinanceTravelDetail)
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
) -> dict:
    since = date.today() - timedelta(days=days - 1)
    stmt = select(FinanceTravelDetail).where(FinanceTravelDetail.detail_date >= since)
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
def create_detail(payload: TravelDetailCreate, db: Session = Depends(get_db)):
    obj = FinanceTravelDetail(** _compute_actual(payload))
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@details_router.put("/{item_id}", response_model=TravelDetailRead)
def update_detail(item_id: int, payload: TravelDetailCreate, db: Session = Depends(get_db)):
    obj = db.get(FinanceTravelDetail, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="记录不存在")
    for key, value in _compute_actual(payload).items():
        setattr(obj, key, value)
    db.commit()
    db.refresh(obj)
    return obj


@details_router.delete("/{item_id}", status_code=204)
def delete_detail(item_id: int, db: Session = Depends(get_db)):
    obj = db.get(FinanceTravelDetail, item_id)
    if not obj:
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


@report_router.post("/report/generate")
def travel_report_generate(payload: ReportGenReq, db: Session = Depends(get_db)):
    start, end = _resolve_period(payload.days, payload.end_date)
    title, summary, content = finance_report.build_travel_report(db, start, end, payload.ledger_id)
    return {"title": title, "summary": summary, "content": content, "start": start, "end": end}


@report_router.get("/report/export")
def travel_report_export(
    ledger_id: int | None = None,
    days: int = Query(30, ge=1, le=365),
    end_date: date | None = None,
    db: Session = Depends(get_db),
):
    start, end = _resolve_period(days, end_date)
    try:
        title, summary, content = finance_report.build_travel_report(db, start, end, ledger_id)
        pdf = finance_report.build_pdf(title=title, summary=summary, content=content)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"PDF 生成失败：{exc}")
    filename = f"旅行开支报告_{start.isoformat()}_{end.isoformat()}.pdf"
    return StreamingResponse(
        BytesIO(pdf),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}"},
    )


# 合并为一个 router 供 __init__ 使用
router = APIRouter()
router.include_router(ledgers_router)
router.include_router(details_router)
router.include_router(report_router)