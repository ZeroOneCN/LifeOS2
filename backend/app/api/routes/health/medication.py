from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import HealthMedPurchase, HealthMedStock, HealthMedication, UserProfile
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


def _medication_stats(db: Session, days: int, user_id: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthMedication)
        .where(HealthMedication.user_id == user_id)
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


# ---- 购药记录 ----
# 相对前缀 /purchases：include 进 /health/medication 路由器后拼成 /health/medication/purchases，
# 且必须在动态 /{item_id} 之前注册，否则 /purchases 会被当作 item_id 解析报 422
purchase_router = crud_router(
    prefix="/purchases",
    tag="health-med-purchase",
    model=HealthMedPurchase,
    create_schema=MedPurchaseCreate,
    read_schema=MedPurchaseRead,
    order_by=HealthMedPurchase.buy_date,
    date_column="buy_date",
)


# ---- 药品库存 / 购药记录（固定静态路由，需在动态 /{item_id} 之前注册） ----
def _register_fixed(router) -> None:
    # 购药记录路由必须注册在 /{item_id} 之前，否则 /purchases 会被当作 item_id 解析报 422
    router.include_router(purchase_router)

    @router.get("/stocks")
    def list_stocks(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        stocks = _get_stock_list(db, user.id)
        return {
            "items": stocks,
            "total": len(stocks),
            "low_count": sum(1 for s in stocks if s["is_low"]),
        }

    @router.post("/stocks", response_model=MedStockRead)
    def upsert_stock(
        payload: MedStockCreate,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        existing = db.scalar(
            select(HealthMedStock).where(
                HealthMedStock.user_id == user.id,
                HealthMedStock.medicine_name == payload.medicine_name,
            )
        )
        if existing:
            for key, value in payload.model_dump().items():
                setattr(existing, key, value)
            db.commit()
            db.refresh(existing)
            return existing
        obj = HealthMedStock(**payload.model_dump(), user_id=user.id)
        db.add(obj)
        db.commit()
        db.refresh(obj)
        return obj

    @router.put("/stocks/{stock_id}", response_model=MedStockRead)
    def update_stock(
        stock_id: int,
        payload: MedStockCreate,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        from fastapi import HTTPException

        obj = db.scalar(
            select(HealthMedStock).where(
                HealthMedStock.id == stock_id,
                HealthMedStock.user_id == user.id,
            )
        )
        if not obj:
            raise HTTPException(status_code=404, detail="库存记录不存在")
        for key, value in payload.model_dump().items():
            setattr(obj, key, value)
        db.commit()
        db.refresh(obj)
        return obj

    @router.delete("/stocks/{stock_id}", status_code=204)
    def delete_stock(
        stock_id: int,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        from fastapi import HTTPException

        obj = db.scalar(
            select(HealthMedStock).where(
                HealthMedStock.id == stock_id,
                HealthMedStock.user_id == user.id,
            )
        )
        if not obj:
            raise HTTPException(status_code=404, detail="库存记录不存在")
        db.delete(obj)
        db.commit()
        return None


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
    extra_routes=_register_fixed,
)


def _get_stock_list(db: Session, user_id: int) -> list[dict]:
    """根据购药记录与用药记录自动计算库存并预测耗尽时间。"""
    stock_rows = db.scalars(
        select(HealthMedStock)
        .where(HealthMedStock.user_id == user_id)
        .order_by(HealthMedStock.medicine_name)
    ).all()
    purchases = db.scalars(
        select(HealthMedPurchase).where(HealthMedPurchase.user_id == user_id)
    ).all()
    meds = db.scalars(
        select(HealthMedication).where(HealthMedication.user_id == user_id)
    ).all()

    # 每种药品的累计购买量
    bought: dict[str, float] = defaultdict(float)
    for p in purchases:
        bought[p.medicine_name] += p.quantity or 0

    # 每种药品的已服用次数（用药记录 taken=True 计为一次消耗）
    taken_dates: dict[str, list[date]] = defaultdict(list)
    for m in meds:
        if m.taken:
            taken_dates[m.medicine_name].append(m.record_date)

    today = date.today()
    rows: list[dict] = []
    for s in stock_rows:
        name = s.medicine_name
        consumed = len(taken_dates.get(name, []))
        stock = max(0.0, round(bought.get(name, 0) - consumed, 2))

        # 预测：按近 consumed 记录的实际区间推算日均消耗
        dates = taken_dates.get(name, [])
        avg_daily: float | None = None
        days_left: float | None = None
        predicted_date: date | None = None
        if dates and stock > 0:
            span_days = max(1, (today - min(dates)).days + 1)
            avg_daily = round(consumed / span_days, 3)
            if avg_daily > 0:
                days_left = int(stock // avg_daily)
                predicted_date = today + timedelta(days=days_left)

        is_low = s.threshold is not None and s.threshold > 0 and stock <= s.threshold
        rows.append(
            {
                "id": s.id,
                "medicine_name": name,
                "stock_qty": stock,
                "threshold": s.threshold,
                "unit": s.unit,
                "is_low": is_low,
                "purchased": round(bought.get(name, 0), 2),
                "consumed": consumed,
                "avg_daily": avg_daily,
                "days_left": days_left,
                "predicted_date": predicted_date.isoformat() if predicted_date else None,
            }
        )
    return rows