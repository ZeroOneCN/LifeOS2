from datetime import datetime

from pydantic import BaseModel, ConfigDict


class RegisterRequest(BaseModel):
    """注册请求。"""

    account: str
    password: str
    username: str | None = None
    nickname: str | None = None


class LoginRequest(BaseModel):
    """登录请求。"""

    account: str
    password: str


class RefreshRequest(BaseModel):
    """刷新访问令牌请求。"""

    refresh_token: str


class UserMe(BaseModel):
    """当前登录用户信息（不暴露密码哈希）。"""

    model_config = ConfigDict(from_attributes=True)

    id: int
    account: str
    username: str | None
    is_admin: bool
    nickname: str
    avatar: str | None
    email: str | None
    created_at: datetime
    updated_at: datetime


class TokenResponse(BaseModel):
    """登录/注册成功后的令牌与用户信息。"""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserMe


class TokenRefreshResponse(BaseModel):
    """刷新令牌成功后的响应。"""

    access_token: str
    token_type: str = "bearer"