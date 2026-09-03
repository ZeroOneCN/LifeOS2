from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    DateTime,
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


class NotificationChannel(TimestampMixin, Base):
    """通知渠道配置：各类外发渠道（邮件/钉钉/飞书/企微/TGBot/Webhook）。"""

    __tablename__ = "notification_channels"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    channel_type: Mapped[str] = mapped_column(String(16), index=True)  # 渠道类型
    name: Mapped[str] = mapped_column(String(64))  # 渠道别名
    config: Mapped[str | None] = mapped_column(Text)  # 渠道参数 JSON（敏感字段加密）
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)  # 是否启用
    recipients: Mapped[str | None] = mapped_column(Text)  # 目标（邮箱等，逗号分隔）
    note: Mapped[str | None] = mapped_column(String(255))


class NotificationTemplate(TimestampMixin, Base):
    """通知模板：按功能(source)配置的默认渲染模板，支持变量。"""

    __tablename__ = "notification_templates"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    source: Mapped[str] = mapped_column(String(64), unique=True, index=True)  # 功能标识
    category: Mapped[str] = mapped_column(String(32), index=True)  # 财务/生活/健康/系统
    name: Mapped[str] = mapped_column(String(128))  # 模板名
    title_template: Mapped[str] = mapped_column(String(256))  # 标题模板
    content_template: Mapped[str] = mapped_column(Text)  # 内容模板
    is_default: Mapped[bool] = mapped_column(Boolean, default=True)  # 是否系统内置默认
    note: Mapped[str | None] = mapped_column(String(255))


class FeatureReminderSetting(TimestampMixin, Base):
    """功能提醒开关：各提醒功能是否触发/提前天数/下发渠道。"""

    __tablename__ = "feature_reminder_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    feature_key: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(128))  # 显示名
    category: Mapped[str] = mapped_column(String(32), index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=False)  # 默认关闭
    advance_days: Mapped[int] = mapped_column(Integer, default=1)  # 提前几天提醒
    channels: Mapped[str | None] = mapped_column(Text)  # 渠道 id 列表 JSON；空=全部启用渠道
    note: Mapped[str | None] = mapped_column(String(255))


class NotificationSendLog(TimestampMixin, Base):
    """发送日志：记录每次渠道外发的结果。"""

    __tablename__ = "notification_send_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    notification_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 关联站内通知
    channel_type: Mapped[str] = mapped_column(String(16), index=True)
    channel_id: Mapped[int | None] = mapped_column(Integer, index=True)
    status: Mapped[str] = mapped_column(String(16), index=True)  # sent/pending/failed
    error: Mapped[str | None] = mapped_column(Text)  # 失败原因
    sent_at: Mapped[datetime | None] = mapped_column(DateTime)  # 发送时间