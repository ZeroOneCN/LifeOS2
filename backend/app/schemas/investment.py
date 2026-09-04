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
    symbol: str
    order_type: str = Field(pattern="^(buy|sell)$")
    open_price: float = Field(ge=0)
    lot_size: float = Field(ge=0)
    commission: float = Field(0.0)
    close_price: float | None = Field(None, ge=0)
    pnl: float | None = None
    overnight_fee: float = Field(0.0)
    open_time: datetime | None = None
    close_time: datetime | None = None
    holding: int | None = Field(None, ge=0, description="持仓时间（分钟，缺省自动计算）")
    status: str = Field("closed", pattern="^(open|closed)$")
    note: str | None = None


class ForexRead(ForexCreate, ORMRead):
    pass


class FundCreate(BaseModel):
    record_type: str = Field(pattern="^(deposit|withdraw|experience)$")
    # 金额可为负：体验金亏损/失效以负数记录，体现余额减少
    amount: float
    record_date: date
    note: str | None = None


class FundRead(FundCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int