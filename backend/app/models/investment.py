from datetime import date, datetime

from sqlalchemy import (
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


class InvestmentForex(TimestampMixin, Base):
    """外汇交易：MT5 交易记录（支持 xlsx 批量导入）。"""

    __tablename__ = "investment_forex"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)  # 交易日期（日期时间）
    symbol: Mapped[str] = mapped_column(String(24), index=True)  # 交易品种 EUR/USD
    order_type: Mapped[str] = mapped_column(String(8))  # buy / sell
    open_price: Mapped[float] = mapped_column(Float)  # 开仓价格
    lot_size: Mapped[float] = mapped_column(Float)  # 手数
    commission: Mapped[float] = mapped_column(Float, default=0.0)  # 手续费
    close_price: Mapped[float | None] = mapped_column(Float)  # 平仓价格
    pnl: Mapped[float | None] = mapped_column(Float)  # 盈亏金额
    overnight_fee: Mapped[float] = mapped_column(Float, default=0.0)  # 隔夜费/库存费
    open_time: Mapped[datetime | None] = mapped_column(DateTime)  # 开仓时间
    close_time: Mapped[datetime | None] = mapped_column(DateTime)  # 平仓时间
    holding: Mapped[int | None] = mapped_column(Integer)  # 持仓时间（分钟，由开平仓时间自动计算）
    status: Mapped[str] = mapped_column(
        String(8), default="closed"
    )  # open / closed
    note: Mapped[str | None] = mapped_column(Text)


class InvestmentFundRecord(TimestampMixin, Base):
    """资金动态：入金 / 出金 / 体验金记录。"""

    __tablename__ = "investment_fund_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_type: Mapped[str] = mapped_column(String(16), index=True)  # deposit/withdraw/experience
    amount: Mapped[float] = mapped_column(Float)  # 金额（正数）
    record_date: Mapped[date] = mapped_column(Date, index=True)  # 发生日期
    note: Mapped[str | None] = mapped_column(Text)


class InvestmentReport(TimestampMixin, Base):
    """投资报告：周期性汇总的投资分析报告。"""

    __tablename__ = "investment_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128))
    period_label: Mapped[str] = mapped_column(String(32))  # YYYY-MM
    period_start: Mapped[date] = mapped_column(Date)
    period_end: Mapped[date] = mapped_column(Date)
    summary: Mapped[str | None] = mapped_column(Text)
    content: Mapped[str | None] = mapped_column(Text)  # JSON 结构化内容