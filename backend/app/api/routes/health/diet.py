from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.api.knowledge.fitness import FOOD_NUTRITION, estimate_nutrition
from app.models import HealthDiet
from app.schemas.health import DietCreate, DietRead

router = APIRouter()


def _diet_stats(db: Session, days: int, user_id: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthDiet)
        .where(HealthDiet.user_id == user_id)
        .where(HealthDiet.record_date >= since)
        .order_by(HealthDiet.record_date)
    ).all()

    by_day: dict[date, dict] = defaultdict(
        lambda: {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "count": 0}
    )
    by_meal: dict[str, dict] = defaultdict(
        lambda: {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "count": 0}
    )
    for r in rows:
        by_day[r.record_date]["calories"] += r.calories or 0
        by_day[r.record_date]["protein"] += r.protein or 0
        by_day[r.record_date]["carbs"] += r.carbs or 0
        by_day[r.record_date]["fat"] += r.fat or 0
        by_day[r.record_date]["count"] += 1
        by_meal[r.meal_type]["calories"] += r.calories or 0
        by_meal[r.meal_type]["protein"] += r.protein or 0
        by_meal[r.meal_type]["carbs"] += r.carbs or 0
        by_meal[r.meal_type]["fat"] += r.fat or 0
        by_meal[r.meal_type]["count"] += 1

    return {
        "trend": [
            {"record_date": d, **{k: round(v, 1) for k, v in v.items()}}
            for d, v in sorted(by_day.items())
        ],
        "by_meal": [
            {"meal_type": k, **{kk: round(vv, 1) for kk, vv in v.items()}}
            for k, v in sorted(by_meal.items())
        ],
        "total_count": len(rows),
        "total_calories": round(sum(r.calories or 0 for r in rows), 1),
        "total_protein": round(sum(r.protein or 0 for r in rows), 1),
        "avg_calories_per_day": (
            round(sum(r.calories or 0 for r in rows) / (len(by_day) or 1), 1)
            if by_day
            else None
        ),
    }


def _register_fixed(router) -> None:

    @router.get("/foods")
    def list_foods(q: str = Query("", max_length=32)):
        """返回内置常见食物营养表（每100g），可按名称过滤。"""
        items = []
        for name, (cal, pro, carb, fat) in FOOD_NUTRITION.items():
            if q and q not in name:
                continue
            items.append(
                {
                    "name": name,
                    "calories": cal,
                    "protein": pro,
                    "carbs": carb,
                    "fat": fat,
                }
            )
        return {"items": items, "total": len(items)}

    @router.get("/estimate")
    def estimate(food_name: str = Query(..., max_length=64), weight_g: float = Query(100, gt=0)):
        """根据食物名称与重量推算营养，供前端自动填写。"""
        return estimate_nutrition(food_name, weight_g)


router = crud_router(
    prefix="/health/diet",
    tag="health-diet",
    model=HealthDiet,
    create_schema=DietCreate,
    read_schema=DietRead,
    order_by=HealthDiet.record_date,
    date_column="record_date",
    stats_func=_diet_stats,
    extra_routes=_register_fixed,
)