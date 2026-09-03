import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models import UserProfile

_bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> tuple[str, str]:
    """生成 (盐, 哈希)，使用 PBKDF2-SHA256。"""
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), bytes.fromhex(salt), 100_000
    ).hex()
    return salt, digest


def verify_password(password: str, salt: str, digest: str) -> bool:
    """校验密码是否匹配。"""
    check = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), bytes.fromhex(salt), 100_000
    ).hex()
    return hmac.compare_digest(check, digest)


def account_exists(db: Session, account: str, exclude_id: int | None = None) -> bool:
    """账号是否已存在（可排除指定记录）。"""
    stmt = select(UserProfile).where(UserProfile.account == account)
    if exclude_id is not None:
        stmt = stmt.where(UserProfile.id != exclude_id)
    return db.scalar(stmt) is not None


def username_exists(db: Session, username: str, exclude_id: int | None = None) -> bool:
    """用户名是否已存在（可排除指定记录）。"""
    stmt = select(UserProfile).where(UserProfile.username == username)
    if exclude_id is not None:
        stmt = stmt.where(UserProfile.id != exclude_id)
    return db.scalar(stmt) is not None


def create_access_token(user_id: int, username: str | None) -> str:
    """生成 JWT 访问令牌。"""
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {"sub": str(user_id), "username": username, "exp": expire}
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token_user_id(token: str | None) -> int | None:
    """无 DB 依赖地解析 JWT 中的用户 id（供中间件等复用）。"""
    if not token:
        return None
    try:
        payload = jwt.decode(
            token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM]
        )
        sub = payload.get("sub")
        return int(sub) if sub is not None else None
    except (jwt.PyJWTError, ValueError, TypeError):
        return None


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(get_db),
) -> UserProfile:
    """解析 JWT 并返回当前登录用户；无效/过期/不存在均返回 401。"""
    if credentials is None:
        raise HTTPException(status_code=401, detail="未登录，请先登录")
    user_id = decode_token_user_id(credentials.credentials)
    if user_id is None:
        raise HTTPException(status_code=401, detail="登录状态无效或已过期，请重新登录")
    profile = db.get(UserProfile, user_id)
    if profile is None:
        raise HTTPException(status_code=401, detail="用户不存在，请重新登录")
    return profile