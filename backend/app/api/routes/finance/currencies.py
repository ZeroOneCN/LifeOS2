from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import FinanceCurrency
from app.schemas.finance import CurrencyCreate

router = APIRouter(prefix="/finance/currencies", tags=["finance-currencies"])

DEFAULT_CURRENCIES = [
    {"currency": "CNY", "name": "人民币", "rate_to_cny": 1.0, "symbol": "¥"},
    {"currency": "USD", "name": "美元", "rate_to_cny": 7.2, "symbol": "$"},
    {"currency": "HKD", "name": "港元", "rate_to_cny": 0.92, "symbol": "HK$"},
]


def _ensure_defaults(db: Session) -> None:
    if db.scalars(select(FinanceCurrency).limit(1)).first():
        return
    for data in DEFAULT_CURRENCIES:
        db.add(FinanceCurrency(**data))
    db.commit()


@router.get("")
def list_currencies(db: Session = Depends(get_db)):
    _ensure_defaults(db)
    rows = db.scalars(select(FinanceCurrency).order_by(FinanceCurrency.currency)).all()
    return [
        {
            "id": r.id,
            "currency": r.currency,
            "name": r.name,
            "rate_to_cny": r.rate_to_cny,
            "symbol": r.symbol,
        }
        for r in rows
    ]


@router.put("/{item_id}")
def update_currency(item_id: int, payload: CurrencyCreate, db: Session = Depends(get_db)):
    obj = db.get(FinanceCurrency, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="币种不存在")
    for key, value in payload.model_dump().items():
        setattr(obj, key, value)
    db.commit()
    db.refresh(obj)
    return {
        "id": obj.id,
        "currency": obj.currency,
        "name": obj.name,
        "rate_to_cny": obj.rate_to_cny,
        "symbol": obj.symbol,
    }


@router.delete("/{item_id}", status_code=204)
def delete_currency(item_id: int, db: Session = Depends(get_db)):
    obj = db.get(FinanceCurrency, item_id)
    if not obj:
        raise HTTPException(status_code=404, detail="币种不存在")
    if obj.currency == "CNY":
        raise HTTPException(status_code=400, detail="人民币基准币种不可删除")
    db.delete(obj)
    db.commit()
    return None