from datetime import date, datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class ItemCreate(BaseModel):
    item_name: str
    category: str
    location: str | None = None
    status: str = Field("in_use", pattern="^(in_use|lost|loaned|recycled)$")
    purchase_date: date | None = None
    price: float | None = Field(None, ge=0)
    expire_date: date | None = None
    end_date: date | None = None
    source: str = Field("manual", pattern="^(manual|shopping)$")
    shopping_record_id: int | None = None
    note: str | None = None


class ItemRead(ItemCreate, ORMRead):
    pass


class PhoneCardCreate(BaseModel):
    phone_number: str
    operator: str
    region: str | None = None
    balance: float | None = Field(None, ge=0)
    monthly_fee: float | None = Field(None, ge=0)
    bill_day: int | None = Field(None, ge=1, le=31)
    data_plan: str | None = None
    call_plan: str | None = None
    sms_plan: str | None = None
    open_date: date | None = None
    billing_type: str = Field("monthly", pattern="^(monthly|one_time|yearly)$")
    bill_paid_this_month: bool = False
    status: str = Field("active", pattern="^(active|frozen|expired|disabled)$")
    note: str | None = None


class PhoneCardRead(PhoneCardCreate, ORMRead):
    pass


class BankCardCreate(BaseModel):
    card_name: str
    card_holder: str | None = None
    bank: str
    card_category: str = Field("debit", pattern="^(credit|debit)$")
    card_form: str = Field("physical", pattern="^(physical|virtual)$")
    card_number: str | None = None
    balance: float | None = Field(None, ge=0)
    credit_limit: float | None = Field(None, ge=0)
    billing_day: int | None = Field(None, ge=1, le=31)
    due_day: int | None = Field(None, ge=1, le=31)
    expire_date: date | None = None
    status: str = Field("active", pattern="^(active|frozen|expired|closed)$")
    note: str | None = None


class BankCardRead(BankCardCreate, ORMRead):
    pass


class CarrierCreate(BaseModel):
    name: str
    website: str | None = None
    contact: str | None = None
    note: str | None = None


class CarrierRead(CarrierCreate, ORMRead):
    pass


class CardBillCreate(BaseModel):
    phone_card_id: int
    bill_month: date
    amount: float = Field(ge=0)
    deducted_date: date | None = None
    paid: bool = True
    note: str | None = None


class CardBillRead(CardBillCreate, ORMRead):
    pass


class LifeReportCreate(BaseModel):
    title: str
    period_label: str
    period_start: date
    period_end: date
    summary: str | None = None
    content: str | None = None


class LifeReportRead(LifeReportCreate, ORMRead):
    pass


class TodoCreate(BaseModel):
    title: str
    category: str | None = None
    priority: str = Field("medium", pattern="^(high|medium|low)$")
    due_date: date | None = None
    done: bool = False
    note: str | None = None


class TodoRead(TodoCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int