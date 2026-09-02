from datetime import date, datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class ForexCreate(BaseModel):
    trade_date: date
    pair: str
    direction: str = Field(pattern="^(buy|sell)$")
    open_price: float = Field(ge=0)
    close_price: float | None = Field(None, ge=0)
    lot_size: float = Field(ge=0)
    pnl: float | None = None
    status: str = Field("closed", pattern="^(open|closed)$")
    note: str | None = None


class ForexRead(ForexCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
