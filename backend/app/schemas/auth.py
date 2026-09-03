from datetime import datetime

from pydantic import BaseModel, ConfigDict


class RegisterRequest(BaseModel):
    """注册请求。"""

    username: str
    password: str
    nickname: str | None = None


class LoginRequest(BaseModel):
    """登录请求。"""

    username: str
    password: str


class UserMe(BaseModel):
    """当前登录用户信息（不暴露密码哈希）。"""

    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str | None
    nickname: str
    avatar: str | None
    email: str | None
    created_at: datetime
    updated_at: datetime


class TokenResponse(BaseModel):
    """登录/注册成功后的令牌与用户信息。"""

    access_token: str
    token_type: str = "bearer"
    user: UserMe