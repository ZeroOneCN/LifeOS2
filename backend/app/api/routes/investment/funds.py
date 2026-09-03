from collections import defaultdict
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import InvestmentFundRecord
from app.schemas.health import PageOut
from app.schemas.investment import FundCreate, FundRead

router = APIRouter(prefix="/investment/funds", tags=["investment-funds"])

_TYPE_LABEL = {"deposit": "入金", "withdraw": "出金", "experience": "体验金"}


class FundSummary(BaseModel):
    deposit: float
    withdraw: float
    experience: float
    net: float
    by_date: list[dict]


@router.get("/stats")
def stats(start: date | None = None, end: date | None = None, db: Session = Depends(get_db)):
    stmt = select(InvestmentFundRecord)
    if start:
        stmt = stmt.where(InvestmentFundRecord.record_date >= start)
    if end:
        stmt = stmt.where(InvestmentFundRecord.record_date <= end)
    rows = db.scalars(stmt.order_by(InvestmentFundRecord.record_date)).all()
    deposit = sum(r.amount for r in rows if r.record_type == "deposit")
    withdraw = sum(r.amount for r in rows if r.record_type == "withdraw")
    experience = sum(r.amount for r in rows if r.record_type == "experience")
    by_date: dict[date, dict] = {}
    for r in rows:
        b = by_date.setdefault(r.record_date, {"date": r.record_date.isoformat(), "deposit": 0.0, "withdraw": 0.0, "experience": 0.0})
        b[r.record_type] = round(b[r.record_type] + r.amount, 2)
    return {
        "deposit": round(deposit, 2),
        "withdraw": round(withdraw, 2),
        "experience": round(experience, 2),
        "net": round(deposit - withdraw + experience, 2),
        "by_date": sorted(by_date.values(), key=lambda x: x["date"]),
    }


@router.get("", response_model=PageOut[FundRead])
def list_items(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    record_type: str | None = None,
    db: Session = Depends(get_db),
):
    stmt = select(InvestmentFundRecord)
    if record_type:
        stmt = stmt.where(InvestmentFundRecord.record_type == record_type)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(
        stmt.order_by(InvestmentFundRecord.record_date.desc(), InvestmentFundRecord.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return PageOut(items=rows, total=total, page=page, page_size=page_size)


@router.post("", response_model=FundRead, status_code=201)
def create_item(payload: FundCreate, db: Session = Depends(get_db)):
    obj = InvestmentFundRecord(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.put("/{item_id}", response_model=FundRead)
def update_item(item_id: int, payload: FundCreate, db: Session = Depends(get_db)):
    obj = db.get(InvestmentFundRecord, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="记录不存在")
    for k, v in payload.model_dump().items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/{item_id}", status_code=204)
def delete_item(item_id: int, db: Session = Depends(get_db)):
    obj = db.get(InvestmentFundRecord, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="记录不存在")
    db.delete(obj)
    db.commit()
    return None