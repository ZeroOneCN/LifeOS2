from collections import defaultdict
from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
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
from app.services.med_stock import compute_med_stock_list

router = APIRouter()

MEAL_LABEL = {"breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐"}
MEAL_ORDER = ["breakfast", "lunch", "dinner"]


def _record_pills(r) -> tuple[list[int], list[bool]]:
    """返回该记录的 (三顿剂量粒数, 三顿是否已服)。"""
    return (
        [r.dose_breakfast or 0, r.dose_lunch or 0, r.dose_dinner or 0],
        [r.taken_breakfast, r.taken_lunch, r.taken_dinner],
    )


def _pill_consumed(r) -> int:
    """该记录已服用消耗的粒数。"""
    total = 0
    for dose, taken in zip(*_record_pills(r), strict=False):
        if taken:
            total += dose
    return total


def _medication_stats(db: Session, days: int, user_id: int) -> dict:
    since = days_since(days)
    stmt = select(HealthMedication).where(HealthMedication.user_id == user_id)
    if since is not None:
        stmt = stmt.where(HealthMedication.record_date >= since)
    rows = db.scalars(
        stmt.order_by(HealthMedication.record_date)
    ).all()

    today = date.today()
    today_items = [r for r in rows if r.record_date == today]

    def _serialize(r) -> dict:
        return {
            "id": r.id,
            "medicine_name": r.medicine_name,
            "dose_breakfast": r.dose_breakfast or 0,
            "dose_lunch": r.dose_lunch or 0,
            "dose_dinner": r.dose_dinner or 0,
            "taken_breakfast": r.taken_breakfast,
            "taken_lunch": r.taken_lunch,
            "taken_dinner": r.taken_dinner,
        }

    by_slot: dict[str, dict] = {m: {"total": 0, "taken": 0} for m in MEAL_ORDER}
    by_day: dict[date, dict] = defaultdict(lambda: {"total": 0, "taken": 0})
    by_med: dict[str, int] = defaultdict(int)
    total_pills = 0
    taken_pills = 0
    for r in rows:
        doses, takens = _record_pills(r)
        planned = sum(doses)
        consumed = _pill_consumed(r)
        total_pills += planned
        taken_pills += consumed
        by_med[r.medicine_name] += 1
        by_day[r.record_date]["total"] += planned
        by_day[r.record_date]["taken"] += consumed
        for i, meal in enumerate(MEAL_ORDER):
            by_slot[meal]["total"] += doses[i]
            if takens[i]:
                by_slot[meal]["taken"] += doses[i]

    today_taken = sum(_pill_consumed(r) for r in today_items)
    today_planned = sum(sum(_record_pills(r)[0]) for r in today_items)

    return {
        "today": {
            "taken_count": today_taken,
            "pending_count": max(0, today_planned - today_taken),
            "items": [_serialize(r) for r in today_items],
        },
        "by_slot": [
            {"meal_slot": k, "meal_label": MEAL_LABEL[k], **by_slot[k]}
            for k in MEAL_ORDER
        ],
        "by_medicine": [
            {"medicine_name": k, "count": v}
            for k, v in sorted(by_med.items(), key=lambda x: -x[1])
        ],
        "adherence_rate": (
            round(taken_pills / total_pills * 100, 1) if total_pills else None
        ),
        "trend": [
            {"record_date": d, **v}
            for d, v in sorted(by_day.items())
        ],
        "total_count": len(rows),
        "total_pills": total_pills,
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
    return compute_med_stock_list(db, user_id)