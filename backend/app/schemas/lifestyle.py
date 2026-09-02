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
    note: str | None = None


class ItemRead(ItemCreate, ORMRead):
    pass


class SimCardCreate(BaseModel):
    card_name: str
    card_type: str
    card_number: str | None = None
    balance: float | None = Field(None, ge=0)
    expire_date: date | None = None
    status: str = Field("active", pattern="^(active|frozen|expired)$")
    note: str | None = None


class SimCardRead(SimCardCreate, ORMRead):
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


class ScheduleCreate(BaseModel):
    schedule_date: date
    start_time: str | None = None
    end_time: str | None = None
    title: str
    location: str | None = None
    category: str | None = None
    note: str | None = None


class ScheduleRead(ScheduleCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
