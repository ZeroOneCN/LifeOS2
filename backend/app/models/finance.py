from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    Integer,
    String,
    Text,
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


class FinancePurchase(TimestampMixin, Base):
    """购买记录：日常消费支出。"""

    __tablename__ = "finance_purchases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    purchase_date: Mapped[date] = mapped_column(Date, index=True)
    item_name: Mapped[str] = mapped_column(String(128))  # 商品名称
    category: Mapped[str] = mapped_column(String(32), index=True)  # 分类
    amount: Mapped[float] = mapped_column(Float)  # 金额
    quantity: Mapped[int | None] = mapped_column(Integer)  # 数量
    store: Mapped[str | None] = mapped_column(String(64))  # 购买渠道
    note: Mapped[str | None] = mapped_column(Text)


class FinanceTravel(TimestampMixin, Base):
    """旅行开支：旅行相关费用。"""

    __tablename__ = "finance_travel"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    expense_date: Mapped[date] = mapped_column(Date, index=True)
    trip_name: Mapped[str] = mapped_column(String(128))  # 行程名称
    category: Mapped[str] = mapped_column(String(32), index=True)  # 交通/住宿/餐饮等
    amount: Mapped[float] = mapped_column(Float)  # 金额
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
