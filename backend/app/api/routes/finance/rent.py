from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import FinanceHousing, FinanceRentChannel, FinanceRentTerm, UserProfile
from app.schemas.finance import RentChannelCreate, RentChannelRead, RentTermCreate, RentTermRead

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


terms_router = APIRouter(prefix="/finance/rent-terms", tags=["finance-rent-terms"])


@terms_router.get("", response_model=list[RentTermRead])
def list_terms(
    housing_id: int = Query(...),
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """返回某住房的期次；期次仅由用户手动新增，无期次时返回空数组。"""
    housing = db.scalars(
        select(FinanceHousing).where(FinanceHousing.id == housing_id, FinanceHousing.user_id == user.id)
    ).first()
    if not housing:
        raise HTTPException(status_code=404, detail="住房不存在")
    return db.scalars(
        select(FinanceRentTerm)
        .where(FinanceRentTerm.housing_id == housing_id, FinanceRentTerm.user_id == user.id)
        .order_by(FinanceRentTerm.term_no)
    ).all()


@terms_router.put("/{term_id}", response_model=RentTermRead)
def update_term(
    term_id: int,
    amount: float | None = None,
    paid: bool | None = None,
    due_date: date | None = None,
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
    if due_date is not None:
        t.due_date = due_date
    db.commit()
    db.refresh(t)
    return t


@terms_router.post("", response_model=RentTermRead, status_code=201)
def create_term(
    payload: RentTermCreate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """手动新增一期（按合同付款方式/价格录入）。"""
    housing = db.scalars(
        select(FinanceHousing).where(FinanceHousing.id == payload.housing_id, FinanceHousing.user_id == user.id)
    ).first()
    if not housing:
        raise HTTPException(status_code=404, detail="住房不存在")
    last = db.scalars(
        select(FinanceRentTerm.term_no)
        .where(FinanceRentTerm.housing_id == payload.housing_id, FinanceRentTerm.user_id == user.id)
        .order_by(FinanceRentTerm.term_no.desc())
    ).first()
    obj = FinanceRentTerm(
        housing_id=payload.housing_id,
        term_no=(last or 0) + 1,
        amount=round(payload.amount, 2),
        due_date=payload.due_date,
        paid=payload.paid,
        user_id=user.id,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@terms_router.delete("/{term_id}", status_code=204)
def delete_term(
    term_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    t = db.get(FinanceRentTerm, term_id)
    if not t or t.user_id != user.id:
        raise HTTPException(status_code=404, detail="期次不存在")
    db.delete(t)
    db.commit()
    return None


router.include_router(terms_router)