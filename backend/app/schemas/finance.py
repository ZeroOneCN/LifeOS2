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


class TravelPaymentChannelCreate(BaseModel):
    name: str


class TravelPaymentChannelRead(TravelPaymentChannelCreate, ORMRead):
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


class HousingCreate(BaseModel):
    name: str
    short_name: str | None = None
    channel: str | None = None
    orientation: str | None = None
    move_in_date: date
    move_out_date: date | None = None
    rent_term: str = Field("monthly", pattern="^(monthly|quarterly)$")
    actual_monthly_rent: float = Field(ge=0)
    deposit: float | None = Field(None, ge=0)
    deposit_refunded: float | None = Field(None, ge=0)  # 已退/已扣押金
    deposit_refund_channel: str | None = None  # 退还渠道（退到哪 / 扣押说明）
    agent_fee: float | None = Field(None, ge=0)
    clean_fee: float | None = Field(None, ge=0)
    service_fee: float | None = Field(None, ge=0)
    laundry_fee: float | None = Field(None, ge=0)
    note: str | None = None


class HousingRead(HousingCreate, ORMRead):
    pass


class RentChannelCreate(BaseModel):
    name: str


class RentChannelRead(RentChannelCreate, ORMRead):
    pass


class RentTermCreate(BaseModel):
    """新增一期：支持手动按合同录入金额/到期日/是否已交。"""
    housing_id: int
    amount: float = Field(ge=0)
    due_date: date
    paid: bool = False


class RentTermRead(RentTermCreate, ORMRead):
    term_no: int


class UtilityCreate(BaseModel):
    housing_id: int | None = None
    bill_month: date
    fee_type: str
    amount: float = Field(ge=0)
    due_date: date | None = None
    paid: bool = False
    note: str | None = None


class UtilityRead(UtilityCreate, ORMRead):
    pass


class SubscriptionCreate(BaseModel):
    name: str
    plan_name: str | None = None
    category: str
    billing_cycle: str = Field("month", pattern="^(month|quarter|year)$")
    amount: float = Field(ge=0)
    start_date: date
    end_date: date | None = None
    auto_renew: bool = False
    remind_days: int = Field(30, ge=0)
    status: str = Field("active", pattern="^(active|expired|cancelled)$")
    note: str | None = None


class SubscriptionRead(SubscriptionCreate, ORMRead):
    pass


class SubscriptionCategoryCreate(BaseModel):
    name: str


class SubscriptionCategoryRead(SubscriptionCategoryCreate, ORMRead):
    pass


class LoanPlatformCreate(BaseModel):
    name: str
    bill_day: int | None = Field(None, ge=1, le=31)
    due_day: int | None = Field(None, ge=1, le=31)
    credit_limit: float | None = Field(None, ge=0)
    note: str | None = None


class LoanPlatformRead(LoanPlatformCreate, ORMRead):
    pass


class LoanBillCreate(BaseModel):
    platform_id: int | None = None
    bill_month: date
    due_date: date | None = None
    amount: float = Field(ge=0)
    interest: float | None = Field(None, ge=0)
    paid_amount: float = Field(default=0, ge=0)
    status: str = Field("pending", pattern="^(pending|partial|cleared)$")
    note: str | None = None


class LoanBillRead(LoanBillCreate, ORMRead):
    pass


class RepaymentCreate(BaseModel):
    bill_id: int | None = None
    repay_date: date
    amount: float = Field(gt=0)
    discount: float | None = Field(None, ge=0)
    method: str | None = None
    note: str | None = None


class RepaymentRead(RepaymentCreate, ORMRead):
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


class InvestmentCreate(BaseModel):
    platform: str
    account: str | None = None
    category: str
    pnl: float
    note: str | None = None


class InvestmentRead(InvestmentCreate, ORMRead):
    pass


class MemoCreate(BaseModel):
    title: str
    content: str | None = None
    memo_date: date | None = None


class MemoRead(MemoCreate, ORMRead):
    pass


class CurrencyCreate(BaseModel):
    currency: str
    name: str | None = None
    rate_to_cny: float = Field(gt=0)
    symbol: str | None = None


class CurrencyRead(CurrencyCreate, ORMRead):
    pass


class DebtRepayPayload(BaseModel):
    repay_date: date
    amount: float = Field(gt=0)


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
