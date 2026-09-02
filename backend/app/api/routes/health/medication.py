from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.models import HealthMedPurchase, HealthMedStock, HealthMedication
from app.schemas.health import (
    MedicationCreate,
    MedicationRead,
    MedPurchaseCreate,
    MedPurchaseRead,
    MedStockCreate,
    MedStockRead,
)

router = APIRouter()

MEAL_LABEL = {"breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐"}


def _medication_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthMedication)
        .where(HealthMedication.record_date >= since)
        .order_by(HealthMedication.record_date)
    ).all()

    today = date.today()
    today_items = [r for r in rows if r.record_date == today]
    taken = [r for r in today_items if r.taken]

    by_day: dict[date, dict] = defaultdict(lambda: {"total": 0, "taken": 0})
    by_slot: dict[str, dict] = defaultdict(lambda: {"total": 0, "taken": 0})
    for r in rows:
        by_day[r.record_date]["total"] += 1
        by_slot[r.meal_slot]["total"] += 1
        if r.taken:
            by_day[r.record_date]["taken"] += 1
            by_slot[r.meal_slot]["taken"] += 1

    by_med: dict[str, int] = defaultdict(int)
    for r in rows:
        by_med[r.medicine_name] += 1

    total_records = len(rows)
    taken_records = sum(1 for r in rows if r.taken)
    return {
        "today": {
            "taken_count": len(taken),
            "pending_count": len(today_items) - len(taken),
            "items": [
                {
                    "id": r.id,
                    "medicine_name": r.medicine_name,
                    "meal_slot": r.meal_slot,
                    "meal_label": MEAL_LABEL.get(r.meal_slot, r.meal_slot),
                    "dosage": r.dosage,
                    "taken": r.taken,
                }
                for r in today_items
            ],
        },
        "by_slot": [
            {"meal_slot": k, "meal_label": MEAL_LABEL.get(k, k), **v}
            for k, v in sorted(by_slot.items())
        ],
        "by_medicine": [
            {"medicine_name": k, "count": v}
            for k, v in sorted(by_med.items(), key=lambda x: -x[1])
        ],
        "adherence_rate": (
            round(taken_records / total_records * 100, 1) if total_records else None
        ),
        "trend": [
            {"record_date": d, **v}
            for d, v in sorted(by_day.items())
        ],
        "total_count": total_records,
    }


# ---- 每日用药（分早/午/晚） ----
router = crud_router(
    prefix="/health/medication",
    tag="health-medication",
    model=HealthMedication,
    create_schema=MedicationCreate,
    read_schema=MedicationRead,
    order_by=HealthMedication.record_date,
    date_column="record_date",
    stats_func=_medication_stats,
)

# ---- 购药记录 ----
purchase_router = crud_router(
    prefix="/health/medication/purchases",
    tag="health-med-purchase",
    model=HealthMedPurchase,
    create_schema=MedPurchaseCreate,
    read_schema=MedPurchaseRead,
    order_by=HealthMedPurchase.buy_date,
    date_column="buy_date",
)
router.include_router(purchase_router)


def _get_stock_list(db: Session) -> list[dict]:
    rows = db.scalars(select(HealthMedStock).order_by(HealthMedStock.medicine_name)).all()
    return [
        {
            "id": s.id,
            "medicine_name": s.medicine_name,
            "stock_qty": s.stock_qty,
            "threshold": s.threshold,
            "unit": s.unit,
            "is_low": s.threshold is not None and s.threshold > 0 and s.stock_qty <= s.threshold,
        }
        for s in rows
    ]


# ---- 药品库存 ----
@router.get("/stocks")
def list_stocks(db: Session = Depends(get_db)):
    stocks = _get_stock_list(db)
    return {
        "items": stocks,
        "total": len(stocks),
        "low_count": sum(1 for s in stocks if s["is_low"]),
    }


@router.post("/stocks", response_model=MedStockRead)
def upsert_stock(payload: MedStockCreate, db: Session = Depends(get_db)):
    existing = db.scalar(
        select(HealthMedStock).where(HealthMedStock.medicine_name == payload.medicine_name)
    )
    if existing:
        for key, value in payload.model_dump().items():
            setattr(existing, key, value)
        db.commit()
        db.refresh(existing)
        return existing
    obj = HealthMedStock(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.put("/stocks/{stock_id}", response_model=MedStockRead)
def update_stock(stock_id: int, payload: MedStockCreate, db: Session = Depends(get_db)):
    obj = db.get(HealthMedStock, stock_id)
    if not obj:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="库存记录不存在")
    for key, value in payload.model_dump().items():
        setattr(obj, key, value)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/stocks/{stock_id}", status_code=204)
def delete_stock(stock_id: int, db: Session = Depends(get_db)):
    from fastapi import HTTPException

    obj = db.get(HealthMedStock, stock_id)
    if not obj:
        raise HTTPException(status_code=404, detail="库存记录不存在")
    db.delete(obj)
    db.commit()
    return None