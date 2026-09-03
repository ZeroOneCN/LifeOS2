from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class NotificationChannelCreate(BaseModel):
    channel_type: str
    name: str
    config: str | None = None
    enabled: bool = True
    recipients: str | None = None
    note: str | None = None


class NotificationChannelRead(NotificationChannelCreate, ORMRead):
    pass


class NotificationTemplateCreate(BaseModel):
    source: str
    category: str
    name: str
    title_template: str
    content_template: str
    is_default: bool = True
    note: str | None = None


class NotificationTemplateRead(NotificationTemplateCreate, ORMRead):
    pass


class FeatureReminderSettingCreate(BaseModel):
    feature_key: str
    name: str
    category: str
    enabled: bool = False
    advance_days: int = 1
    channels: str | None = None
    note: str | None = None


class FeatureReminderSettingRead(FeatureReminderSettingCreate, ORMRead):
    pass


class NotificationSendLogCreate(BaseModel):
    notification_id: int | None = None
    channel_type: str
    channel_id: int | None = None
    status: str
    error: str | None = None
    sent_at: datetime | None = None


class NotificationSendLogRead(NotificationSendLogCreate, ORMRead):
    pass


class TestSendPayload(BaseModel):
    channel_id: int
    title: str | None = None
    content: str | None = None
