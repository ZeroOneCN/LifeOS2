from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, field_validator

from app.services.avatar_storage import is_local_avatar, validate_avatar_url


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

    @field_validator("avatar")
    @classmethod
    def _validate_avatar(cls, value: str | None) -> str | None:
        """头像仅允许 http/https 外链或本站上传地址，空串按清空处理。

        Args:
            value: 请求传入的头像字段。

        Returns:
            规范化后的头像地址或 None。

        Raises:
            ValueError: scheme 非 http/https 或地址格式非法。
        """
        if value is None:
            return None
        value = value.strip()
        if not value:
            return None
        if is_local_avatar(value):
            return value
        return validate_avatar_url(value)


class UserAvatarRead(BaseModel):
    """头像设置结果：本站上传返回相对路径，外链原样返回，清空返回 null。"""

    avatar: str | None


class UserAvatarUrlUpdate(BaseModel):
    """外链方式设置头像：avatar_url 为 null 表示清空头像。"""

    avatar_url: str | None


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
