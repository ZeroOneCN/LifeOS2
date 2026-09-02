from datetime import date, datetime, time
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class ShoppingPlatformCreate(BaseModel):
    name: str


class ShoppingPlatformRead(ShoppingPlatformCreate, ORMRead):
    pass


class ShoppingLedgerCreate(BaseModel):
    name: str


class ShoppingLedgerRead(ShoppingLedgerCreate, ORMRead):
    pass


class ShoppingCreate(BaseModel):
    record_date: date
    platform_id: int | None = None
    product_name: str
    spec: str | None = None
    total_price: float = Field(ge=0)
    unit_price: float | None = Field(None, ge=0)
    order_no: str | None = None
    ledger_id: int | None = None
    note: str | None = None


class ShoppingRead(ShoppingCreate, ORMRead):
    pass


class TravelLedgerCreate(BaseModel):
    name: str
    start_date: date | None = None
    end_date: date | None = None
    note: str | None = None


class TravelLedgerRead(TravelLedgerCreate, ORMRead):
    pass


class TravelDetailCreate(BaseModel):
    ledger_id: int | None = None
    detail_date: date
    begin_time: time | None = None
    end_time: time | None = None
    category: str
    item: str
    original_price: float = Field(ge=0)
    discount: float = Field(default=0, ge=0)
    actual_price: float | None = Field(None, ge=0)
    transport_info: str | None = None
    payment_method: str | None = None
    note: str | None = None


class TravelDetailRead(TravelDetailCreate, ORMRead):
    pass


class BillCreate(BaseModel):
    bill_date: date
    bill_type: str
    amount: float = Field(ge=0)
    due_date: date | None = None
    paid: bool = False
    note: str | None = None


class BillRead(BillCreate, ORMRead):
    pass


class ReminderCreate(BaseModel):
    reminder_date: date
    title: str
    category: str
    amount: float | None = Field(None, ge=0)
    due_date: date | None = None
    status: str = Field("pending", pattern="^(pending|done)$")
    note: str | None = None


class ReminderRead(ReminderCreate, ORMRead):
    pass


class PlanCreate(BaseModel):
    plan_date: date
    plan_type: str
    title: str
    target_amount: float | None = Field(None, ge=0)
    saved_amount: float | None = Field(None, ge=0)
    status: str = Field("active", pattern="^(active|done|abandoned)$")
    note: str | None = None


class PlanRead(PlanCreate, ORMRead):
    pass


class DebtCreate(BaseModel):
    debt_date: date
    name: str
    direction: str = Field(pattern="^(lend|borrow)$")
    counterparty: str | None = None
    amount: float = Field(ge=0)
    remaining: float | None = Field(None, ge=0)
    interest_rate: float | None = Field(None, ge=0)
    due_date: date | None = None
    status: str = Field("active", pattern="^(active|settled)$")
    note: str | None = None


class DebtRead(DebtCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
