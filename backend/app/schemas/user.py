from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class UserProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nickname: str
    avatar: str | None
    gender: str | None
    birthday: date | None
    phone: str | None
    email: str | None
    location: str | None
    job_title: str | None
    bio: str | None
    signature: str | None
    created_at: datetime
    updated_at: datetime


class UserProfileUpdate(BaseModel):
    """个人资料更新：所有字段可选，仅更新传入的字段。"""

    nickname: str | None = None
    avatar: str | None = None
    gender: str | None = None
    birthday: date | None = None
    phone: str | None = None
    email: str | None = None
    location: str | None = None
    job_title: str | None = None
    bio: str | None = None
    signature: str | None = None


class UserSettingsRead(BaseModel):
    """账号设置读取：不暴露密码哈希。"""

    model_config = ConfigDict(from_attributes=True)

    account: str
    username: str | None
    has_password: bool
    created_at: datetime
    updated_at: datetime


class UserSettingsUpdate(BaseModel):
    """账号设置更新：用户名可选；提供 new_password 时执行设置/修改密码。"""

    username: str | None = None
    current_password: str | None = None
    new_password: str | None = None
