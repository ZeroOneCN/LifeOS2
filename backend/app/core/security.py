import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

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
    """生成 JWT 访问令牌（短期，默认 2 小时）。"""
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {"sub": str(user_id), "username": username, "exp": expire, "type": "access"}
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(user_id: int) -> str:
    """生成 JWT 刷新令牌（长期，默认 7 天），type=refresh 用于区分访问令牌。"""
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.REFRESH_TOKEN_EXPIRE_DAYS
    )
    payload = {"sub": str(user_id), "exp": expire, "type": "refresh"}
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def hash_refresh_token(token: str) -> str:
    """对刷新令牌做 SHA-256 哈希，用于数据库存储（不存明文）。"""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def decode_token(token: str | None) -> dict[str, Any] | None:
    """解析 JWT payload，失败返回 None（不校验类型，由调用方判断）。"""
    if not token:
        return None
    try:
        return jwt.decode(
            token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM]
        )
    except (jwt.PyJWTError, ValueError, TypeError):
        return None


def decode_token_user_id(token: str | None) -> int | None:
    """无 DB 依赖地解析 JWT 中的用户 id（供中间件等复用）。"""
    payload = decode_token(token)
    if payload is None:
        return None
    sub = payload.get("sub")
    return int(sub) if sub is not None else None


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(get_db),
) -> UserProfile:
    """解析 JWT 并返回当前登录用户；无效/过期/不存在均返回 401。"""
    if credentials is None:
        raise HTTPException(status_code=401, detail="未登录，请先登录")
    payload = decode_token(credentials.credentials)
    if payload is None or payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="登录状态无效或已过期，请重新登录")
    user_id = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=401, detail="登录状态无效或已过期，请重新登录")
    profile = db.get(UserProfile, int(user_id))
    if profile is None:
        raise HTTPException(status_code=401, detail="用户不存在，请重新登录")
    return profile


def get_current_admin(user: UserProfile = Depends(get_current_user)) -> UserProfile:
    """在登录校验基础上要求管理员身份，用于系统级配置的写操作。"""
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="仅管理员可执行该操作")
    return user


# ── 登录失败锁定（内存计数，进程重启后重置） ──────────────────────────────

_login_failures: dict[str, dict[str, Any]] = {}


def _is_locked(account: str) -> tuple[bool, int]:
    """检查账号是否被锁定，返回 (是否锁定, 剩余锁定秒数)。"""
    info = _login_failures.get(account)
    if not info:
        return False, 0
    lock_until: datetime = info["lock_until"]
    if lock_until > datetime.now():
        remaining = int((lock_until - datetime.now()).total_seconds())
        return True, remaining
    # 锁定已过期，清除记录
    _login_failures.pop(account, None)
    return False, 0


def record_login_failure(account: str) -> None:
    """记录一次登录失败，达到阈值后锁定账号。"""
    info = _login_failures.get(account, {"count": 0, "lock_until": None})
    info["count"] += 1
    if info["count"] >= settings.LOGIN_MAX_FAILURES:
        info["lock_until"] = datetime.now() + timedelta(
            minutes=settings.LOGIN_LOCK_MINUTES
        )
    _login_failures[account] = info


def clear_login_failures(account: str) -> None:
    """登录成功后清除该账号的失败计数。"""
    _login_failures.pop(account, None)