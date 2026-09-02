import calendar
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.models import FinanceHousing, FinanceUtility
from app.schemas.finance import HousingCreate, HousingRead, UtilityCreate, UtilityRead

router = APIRouter()

housing_router = crud_router(
    prefix="/finance/housing",
    tag="finance-housing",
    model=FinanceHousing,
    create_schema=HousingCreate,
    read_schema=HousingRead,
    order_by=FinanceHousing.move_in_date,
    date_column="move_in_date",
)


@router.get("/finance/housing/stats")
def housing_stats(month: str | None = Query(None, description="YYYY-MM，默认当前月"), db: Session = Depends(get_db)) -> dict:
    """住房统计：组合月租（多套并租折算）、押金/杂费汇总、单日成本。"""
    target = _parse_month(month)
    year, mon = target.year, target.month
    days_in_month = calendar.monthrange(year, mon)[1]
    m_start = date(year, mon, 1)
    m_end = date(year, mon, days_in_month)

    houses = db.scalars(select(FinanceHousing).order_by(FinanceHousing.move_in_date)).all()

    detail = []
    combined = 0.0
    total_deposit = 0.0
    total_fees = 0.0
    for h in houses:
        base = h.actual_monthly_rent / (3 if h.rent_term == "quarterly" else 1)
        start = max(h.move_in_date, m_start)
        end = min(h.move_out_date, m_end) if h.move_out_date else m_end
        if start <= m_end and end >= m_start and end > start:
            overlap_days = (end - start).days + 1
            contribution = base * overlap_days / days_in_month
        else:
            overlap_days = 0
            contribution = 0.0
        combined += contribution
        total_deposit += h.deposit or 0
        total_fees += (h.agent_fee or 0) + (h.clean_fee or 0) + (h.service_fee or 0) + (h.laundry_fee or 0)
        detail.append(
            {
                "id": h.id,
                "name": h.name,
                "short_name": h.short_name,
                "channel": h.channel,
                "orientation": h.orientation,
                "move_in_date": h.move_in_date.isoformat(),
                "move_out_date": h.move_out_date.isoformat() if h.move_out_date else None,
                "rent_term": h.rent_term,
                "actual_monthly_rent": h.actual_monthly_rent,
                "deposit": h.deposit or 0,
                "agent_fee": h.agent_fee or 0,
                "clean_fee": h.clean_fee or 0,
                "service_fee": h.service_fee or 0,
                "laundry_fee": h.laundry_fee or 0,
                "overlap_days": overlap_days,
                "single_day_cost": round(base / days_in_month, 2) if overlap_days else 0,
                "monthly_contribution": round(contribution, 2),
            }
        )

    return {
        "month": target.isoformat()[:7],
        "days_in_month": days_in_month,
        "combined_monthly_rent": round(combined, 2),
        "total_deposit": round(total_deposit, 2),
        "total_fees": round(total_fees, 2),
        "house_count": len(houses),
        "houses": detail,
    }


def _parse_month(month: str | None) -> date:
    if not month:
        today = date.today()
        return date(today.year, today.month, 1)
    try:
        y, m = month.split("-")
        return date(int(y), int(m), 1)
    except ValueError:
        today = date.today()
        return date(today.year, today.month, 1)


router.include_router(housing_router)


utilities_router = crud_router(
    prefix="/finance/utilities",
    tag="finance-utilities",
    model=FinanceUtility,
    create_schema=UtilityCreate,
    read_schema=UtilityRead,
    order_by=FinanceUtility.bill_month,
    date_column="bill_month",
)
router.include_router(utilities_router)