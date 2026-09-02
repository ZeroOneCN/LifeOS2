from datetime import date, datetime

from sqlalchemy import Date, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class UserProfile(Base):
    """用户中心：个人基本资料（单记录，id 固定为 1）。"""

    __tablename__ = "user_profile"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    nickname: Mapped[str] = mapped_column(String(64), default="未命名用户")  # 昵称
    avatar: Mapped[str | None] = mapped_column(String(255))  # 头像地址
    gender: Mapped[str | None] = mapped_column(String(16))  # male/female/other
    birthday: Mapped[date | None] = mapped_column(Date)  # 生日
    phone: Mapped[str | None] = mapped_column(String(32))  # 手机号
    email: Mapped[str | None] = mapped_column(String(128))  # 邮箱
    location: Mapped[str | None] = mapped_column(String(128))  # 所在地区
    job_title: Mapped[str | None] = mapped_column(String(64))  # 职业
    bio: Mapped[str | None] = mapped_column(Text)  # 个人简介
    signature: Mapped[str | None] = mapped_column(String(255))  # 个性签名
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )
