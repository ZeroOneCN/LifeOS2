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


class LifestyleItem(TimestampMixin, Base):
    """物品追踪：个人物品管理。"""

    __tablename__ = "lifestyle_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_name: Mapped[str] = mapped_column(String(128), index=True)  # 物品名称
    category: Mapped[str] = mapped_column(String(32), index=True)  # 分类
    location: Mapped[str | None] = mapped_column(String(64))  # 存放位置
    status: Mapped[str] = mapped_column(
        String(16), default="in_use"
    )  # in_use/lost/loaned/recycled
    purchase_date: Mapped[date | None] = mapped_column(Date)  # 购买日期
    price: Mapped[float | None] = mapped_column(Float)  # 价格
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleSimCard(TimestampMixin, Base):
    """卡片管理：手机卡、银行卡等卡片。"""

    __tablename__ = "lifestyle_sim_cards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    card_name: Mapped[str] = mapped_column(String(64), index=True)  # 卡片名称
    card_type: Mapped[str] = mapped_column(String(32), index=True)  # 类型
    card_number: Mapped[str | None] = mapped_column(String(64))  # 卡号
    balance: Mapped[float | None] = mapped_column(Float)  # 余额
    expire_date: Mapped[date | None] = mapped_column(Date)  # 到期日
    status: Mapped[str] = mapped_column(
        String(16), default="active"
    )  # active/frozen/expired
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleTodo(TimestampMixin, Base):
    """待办清单：待办事项。"""

    __tablename__ = "lifestyle_todos"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128), index=True)  # 事项
    category: Mapped[str | None] = mapped_column(String(32))  # 分类
    priority: Mapped[str] = mapped_column(
        String(8), default="medium"
    )  # high/medium/low
    due_date: Mapped[date | None] = mapped_column(Date)  # 截止日期
    done: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否完成
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleSchedule(TimestampMixin, Base):
    """日程管理：日程安排。"""

    __tablename__ = "lifestyle_schedule"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    schedule_date: Mapped[date] = mapped_column(Date, index=True)  # 日期
    start_time: Mapped[str | None] = mapped_column(String(8))  # 开始时间 HH:MM
    end_time: Mapped[str | None] = mapped_column(String(8))  # 结束时间 HH:MM
    title: Mapped[str] = mapped_column(String(128))  # 日程标题
    location: Mapped[str | None] = mapped_column(String(64))  # 地点
    category: Mapped[str | None] = mapped_column(String(32))  # 分类
    note: Mapped[str | None] = mapped_column(Text)
