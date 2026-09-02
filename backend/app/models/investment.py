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
    """外汇交易：外汇交易记录。"""

    __tablename__ = "investment_forex"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    trade_date: Mapped[date] = mapped_column(Date, index=True)
    pair: Mapped[str] = mapped_column(String(16), index=True)  # 货币对 EUR/USD
    direction: Mapped[str] = mapped_column(String(8))  # buy/sell
    open_price: Mapped[float] = mapped_column(Float)  # 开仓价
    close_price: Mapped[float | None] = mapped_column(Float)  # 平仓价
    lot_size: Mapped[float] = mapped_column(Float)  # 手数
    pnl: Mapped[float | None] = mapped_column(Float)  # 盈亏
    status: Mapped[str] = mapped_column(
        String(8), default="closed"
    )  # open/closed
    note: Mapped[str | None] = mapped_column(Text)
