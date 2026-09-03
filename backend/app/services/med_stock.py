"""药品按粒库存计算（共享）：供库存路由与通知扫描器复用。

库存 = 累计购入粒数(Σ 盒/瓶数 × 每盒/瓶粒数) − 已服用粒数，
并按近端已服用记录推算日均消耗，预测耗尽日期。
"""
from collections import defaultdict
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import HealthMedPurchase, HealthMedStock, HealthMedication

_MEAL_TAKEN = ("taken_breakfast", "taken_lunch", "taken_dinner")


def _consumed_pills(m) -> int:
    doses = [
        m.dose_breakfast or 0,
        m.dose_lunch or 0,
        m.dose_dinner or 0,
    ]
    return sum(d for d, taken in zip(doses, (getattr(m, k) for k in _MEAL_TAKEN), strict=True) if taken)


def compute_med_stock_list(db: Session, user_id: int) -> list[dict]:
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

    bought_pills: dict[str, float] = defaultdict(float)
    for p in purchases:
        per = p.pills_per_unit if p.pills_per_unit is not None else 1
        bought_pills[p.medicine_name] += (p.quantity or 0) * per

    consumed_dates: dict[str, list[date]] = defaultdict(list)
    consumed_total: dict[str, int] = defaultdict(int)
    for m in meds:
        taken_pills = _consumed_pills(m)
        if taken_pills > 0:
            consumed_dates[m.medicine_name].append(m.record_date)
            consumed_total[m.medicine_name] += taken_pills

    today = date.today()
    rows = []
    for s in stock_rows:
        name = s.medicine_name
        consumed = consumed_total.get(name, 0)
        stock = max(0.0, round(bought_pills.get(name, 0) - consumed, 2))

        dates = consumed_dates.get(name, [])
        avg_daily = None
        days_left = None
        predicted_date = None
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
                "unit": "粒",
                "is_low": is_low,
                "purchased": round(bought_pills.get(name, 0), 2),
                "consumed": consumed,
                "total_pills": round(bought_pills.get(name, 0), 2),
                "avg_daily": avg_daily,
                "days_left": days_left,
                "predicted_date": predicted_date.isoformat() if predicted_date else None,
            }
        )
    return rows