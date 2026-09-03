from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models.mixins import UserOwned


class TimestampMixin:
    """公共时间戳字段。"""

    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )


class Notification(TimestampMixin, UserOwned, Base):
    """通知中心：系统与业务通知消息。"""

    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128), index=True)  # 通知标题
    content: Mapped[str | None] = mapped_column(Text)  # 通知内容
    category: Mapped[str] = mapped_column(String(32), index=True)  # 系统/健康/财务等
    source: Mapped[str | None] = mapped_column(String(64))  # 来源模块
    read: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否已读
    notify_date: Mapped[date] = mapped_column(Date, index=True)  # 通知日期
    note: Mapped[str | None] = mapped_column(Text)
