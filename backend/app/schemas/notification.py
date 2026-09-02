from datetime import date, datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class NotificationCreate(BaseModel):
    title: str
    content: str | None = None
    category: str
    source: str | None = None
    read: bool = False
    notify_date: date
    note: str | None = None


class NotificationRead(NotificationCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
