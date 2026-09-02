from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    Integer,
    String,
    Text,
    Time,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class TimestampMixin:
    """公共时间戳字段。"""

    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )


class FinanceShoppingPlatform(TimestampMixin, Base):
    """购物平台：可添加管理的电商平台（淘宝/京东等）。"""

    __tablename__ = "finance_shopping_platforms"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), unique=True)  # 平台名称


class FinanceShoppingLedger(TimestampMixin, Base):
    """购物账本：用于分类管理不同场景的购物记录。"""

    __tablename__ = "finance_shopping_ledgers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), unique=True)  # 账本名称


class FinanceShoppingRecord(TimestampMixin, Base):
    """购物记录：具体的购物明细，支持多账本与 xlsx 批量导入。"""

    __tablename__ = "finance_shopping_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)  # 日期
    platform_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 平台 id
    product_name: Mapped[str] = mapped_column(String(128))  # 商品名称
    spec: Mapped[str | None] = mapped_column(String(128))  # 规格
    total_price: Mapped[float] = mapped_column(Float)  # 总价
    unit_price: Mapped[float | None] = mapped_column(Float)  # 单价
    order_no: Mapped[str | None] = mapped_column(String(64), index=True)  # 订单号
    ledger_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 账本 id
    note: Mapped[str | None] = mapped_column(Text)


class FinanceTravelLedger(TimestampMixin, Base):
    """行程账本：一次旅行的总览（多账本，随时切换）。"""

    __tablename__ = "finance_travel_ledgers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(128))  # 行程名称
    start_date: Mapped[date | None] = mapped_column(Date)  # 开始日期
    end_date: Mapped[date | None] = mapped_column(Date)  # 结束日期
    note: Mapped[str | None] = mapped_column(Text)


class FinanceTravelDetail(TimestampMixin, Base):
    """行程明细：一条旅行费用/日程，自动计算时长与实付。"""

    __tablename__ = "finance_travel_details"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ledger_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 行程账本 id
    detail_date: Mapped[date] = mapped_column(Date, index=True)  # 日期
    begin_time: Mapped[Time | None] = mapped_column(Time)  # 开始时间
    end_time: Mapped[Time | None] = mapped_column(Time)  # 结束时间
    category: Mapped[str] = mapped_column(String(32), index=True)  # 分类：交通/住宿/餐饮/门票等
    item: Mapped[str] = mapped_column(String(128))  # 项目
    original_price: Mapped[float] = mapped_column(Float)  # 原价
    discount: Mapped[float] = mapped_column(Float, default=0)  # 优惠
    actual_price: Mapped[float] = mapped_column(Float)  # 实付 = 原价 - 优惠
    transport_info: Mapped[str | None] = mapped_column(String(128))  # 交通信息（航班/车次等）
    payment_method: Mapped[str | None] = mapped_column(String(32))  # 支付方式
    note: Mapped[str | None] = mapped_column(Text)


class FinanceBill(TimestampMixin, Base):
    """账单管理：生活缴费账单。"""

    __tablename__ = "finance_bills"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    bill_date: Mapped[date] = mapped_column(Date, index=True)  # 出账日期
    bill_type: Mapped[str] = mapped_column(String(32), index=True)  # 水/电/燃气等
    amount: Mapped[float] = mapped_column(Float)  # 金额
    due_date: Mapped[date | None] = mapped_column(Date)  # 到期日
    paid: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否已支付
    note: Mapped[str | None] = mapped_column(Text)


class FinanceReminder(TimestampMixin, Base):
    """账单提醒：待办缴费/还款提醒。"""

    __tablename__ = "finance_reminders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    reminder_date: Mapped[date] = mapped_column(Date, index=True)
    title: Mapped[str] = mapped_column(String(128))  # 提醒标题
    category: Mapped[str] = mapped_column(String(32), index=True)  # 类型
    amount: Mapped[float | None] = mapped_column(Float)  # 金额
    due_date: Mapped[date | None] = mapped_column(Date)  # 截止日期
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending/done
    note: Mapped[str | None] = mapped_column(Text)


class FinancePlan(TimestampMixin, Base):
    """财务规划：储蓄/预算/投资等目标。"""

    __tablename__ = "finance_planning"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    plan_date: Mapped[date] = mapped_column(Date, index=True)
    plan_type: Mapped[str] = mapped_column(String(32), index=True)  # 储蓄/预算/投资/目标
    title: Mapped[str] = mapped_column(String(128))  # 目标名称
    target_amount: Mapped[float | None] = mapped_column(Float)  # 目标金额
    saved_amount: Mapped[float | None] = mapped_column(Float)  # 已存金额
    status: Mapped[str] = mapped_column(String(16), default="active")  # active/done/abandoned
    note: Mapped[str | None] = mapped_column(Text)


class FinanceDebt(TimestampMixin, Base):
    """债务管理：借出/借入款项追踪。"""

    __tablename__ = "finance_debts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    debt_date: Mapped[date] = mapped_column(Date, index=True)  # 借款/出借日期
    name: Mapped[str] = mapped_column(String(128))  # 债务名称
    direction: Mapped[str] = mapped_column(String(8), index=True)  # lend=借出 / borrow=借入
    counterparty: Mapped[str | None] = mapped_column(String(64))  # 对方（借款人/债权人）
    amount: Mapped[float] = mapped_column(Float)  # 总金额（本金）
    remaining: Mapped[float | None] = mapped_column(Float)  # 剩余未还/未收金额
    interest_rate: Mapped[float | None] = mapped_column(Float)  # 年利率（%）
    due_date: Mapped[date | None] = mapped_column(Date)  # 到期日
    status: Mapped[str] = mapped_column(String(16), default="active")  # active=进行中 / settled=已结清
    note: Mapped[str | None] = mapped_column(Text)
