from datetime import date, datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class PurchaseCreate(BaseModel):
    purchase_date: date
    item_name: str
    category: str
    amount: float = Field(ge=0)
    quantity: int | None = Field(None, ge=1)
    store: str | None = None
    note: str | None = None


class PurchaseRead(PurchaseCreate, ORMRead):
    pass


class TravelCreate(BaseModel):
    expense_date: date
    trip_name: str
    category: str
    amount: float = Field(ge=0)
    note: str | None = None


class TravelRead(TravelCreate, ORMRead):
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
