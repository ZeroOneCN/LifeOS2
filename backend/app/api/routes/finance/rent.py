from datetime import date, timedelta
from calendar import monthrange

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import FinanceHousing, FinanceRentChannel, FinanceRentTerm, UserProfile
from app.schemas.finance import RentChannelCreate, RentChannelRead, RentTermRead

router = APIRouter()

rent_channels_router = crud_router(
    prefix="/finance/rent-channels",
    tag="finance-rent-channels",
    model=FinanceRentChannel,
    create_schema=RentChannelCreate,
    read_schema=RentChannelRead,
    order_by=FinanceRentChannel.id,
)
router.include_router(rent_channels_router)


def _monthly(term: str) -> int:
    return 3 if term == "quarterly" else 1


def _add_months(d: date, months: int) -> date:
    m = d.month - 1 + months
    y = d.year + m // 12
    mo = m % 12 + 1
    day = min(d.day, monthrange(y, mo)[1])
    return date(y, mo, day)


def _build_terms(housing: FinanceHousing) -> list[dict]:
    """按支付周期从入住日到退租/到期日生成期次；最后一期不足整期按日折算。"""
    monthly = housing.actual_monthly_rent or 0
    months = _monthly(housing.rent_term)
    end = housing.move_out_date or date.today()
    daily = monthly / 30.0
    terms = []
    no = 1
    cur = housing.move_in_date
    while cur < end:
        next_d = _add_months(cur, months)
        if next_d > end:
            # 最后一期不足整期：按剩余天数（含首尾日）折算
            rem_days = (end - cur).days + 1
            amount = round(daily * rem_days, 2) if rem_days > 0 else round(monthly * months, 2)
            due = end
        else:
            amount = round(monthly * months, 2)
            due = next_d - timedelta(days=1)
        terms.append({"term_no": no, "amount": amount, "due_date": due})
        no += 1
        cur = next_d
    if not terms:  # 起始即满，给一期
        terms.append({"term_no": 1, "amount": round(monthly * months, 2), "due_date": end})
    return terms


def _rebuild(db: Session, housing: FinanceHousing):
    """幂等：删除旧期次再按当前参数重新生成（会重置已交标记，用于参数变更后重建）。"""
    db.query(FinanceRentTerm).filter(FinanceRentTerm.housing_id == housing.id).delete()
    for t in _build_terms(housing):
        db.add(FinanceRentTerm(housing_id=housing.id, term_no=t["term_no"], amount=t["amount"], due_date=t["due_date"], user_id=housing.user_id))
    db.commit()


terms_router = APIRouter(prefix="/finance/rent-terms", tags=["finance-rent-terms"])


@terms_router.get("", response_model=list[RentTermRead])
def list_terms(
    housing_id: int = Query(...),
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """返回某住房的期次；若尚未生成则按当前住房参数自动生成。"""
    housing = db.scalars(
        select(FinanceHousing).where(FinanceHousing.id == housing_id, FinanceHousing.user_id == user.id)
    ).first()
    if not housing:
        raise HTTPException(status_code=404, detail="住房不存在")
    existing = db.scalars(
        select(FinanceRentTerm)
        .where(FinanceRentTerm.housing_id == housing_id, FinanceRentTerm.user_id == user.id)
        .order_by(FinanceRentTerm.term_no)
    ).all()
    if not existing:
        for t in _build_terms(housing):
            db.add(FinanceRentTerm(housing_id=housing_id, term_no=t["term_no"], amount=t["amount"], due_date=t["due_date"], user_id=user.id))
        db.commit()
        existing = db.scalars(
            select(FinanceRentTerm)
            .where(FinanceRentTerm.housing_id == housing_id, FinanceRentTerm.user_id == user.id)
            .order_by(FinanceRentTerm.term_no)
        ).all()
    return existing


@terms_router.put("/{term_id}", response_model=RentTermRead)
def update_term(
    term_id: int,
    amount: float | None = None,
    paid: bool | None = None,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    t = db.get(FinanceRentTerm, term_id)
    if not t or t.user_id != user.id:
        raise HTTPException(status_code=404, detail="期次不存在")
    if amount is not None:
        t.amount = round(amount, 2)
    if paid is not None:
        t.paid = paid
    db.commit()
    db.refresh(t)
    return t


@terms_router.post("/rebuild")
def rebuild_terms(
    housing_id: int = Query(...),
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """住房参数变化后手动重建期次。"""
    housing = db.scalars(
        select(FinanceHousing).where(FinanceHousing.id == housing_id, FinanceHousing.user_id == user.id)
    ).first()
    if not housing:
        raise HTTPException(status_code=404, detail="住房不存在")
    _rebuild(db, housing)
    return {"ok": True}


router.include_router(terms_router)