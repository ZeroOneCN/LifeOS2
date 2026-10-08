import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models import LoginAudit, UserProfile, UserSession

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


def create_access_token(user_id: int, username: str | None, session_id: int | None = None) -> str:
    """生成 JWT 访问令牌（短期，默认 2 小时）。

    session_id 用于强制下线校验：验证时需确认该会话仍存在，否则视为已登出。
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {
        "sub": str(user_id),
        "username": username,
        "exp": expire,
        "type": "access",
        "sid": session_id,
    }
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
    """解析 JWT 并返回当前登录用户；无效/过期/不存在/会话已撤销均返回 401。"""
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

    # 会话校验：若令牌携带 sid，则确认对应会话仍存在（被强制下线的会话已被删除）
    session_id = payload.get("sid")
    if session_id is not None:
        session = db.get(UserSession, int(session_id))
        if session is None:
            raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    return profile


def get_current_admin(user: UserProfile = Depends(get_current_user)) -> UserProfile:
    """在登录校验基础上要求管理员身份，用于系统级配置的写操作。"""
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="仅管理员可执行该操作")
    return user


# ── 登录失败锁定（基于 login_audits 表持久化，进程重启不丢失） ────────────


def is_account_locked(db: Session, account: str) -> tuple[bool, int]:
    """检查账号是否处于锁定状态：锁定窗口内存在 result='locked' 记录。

    返回 (是否锁定, 剩余锁定秒数)。锁定窗口由 LOGIN_LOCK_MINUTES 控制，
    从最近一次 locked 记录的时间起算。
    """
    since = datetime.now() - timedelta(minutes=settings.LOGIN_LOCK_MINUTES)
    last_locked = db.scalar(
        select(LoginAudit)
        .where(
            LoginAudit.account == account,
            LoginAudit.result == "locked",
            LoginAudit.created_at >= since,
        )
        .order_by(LoginAudit.created_at.desc())
        .limit(1)
    )
    if not last_locked:
        return False, 0
    lock_until = last_locked.created_at + timedelta(
        minutes=settings.LOGIN_LOCK_MINUTES
    )
    now = datetime.now()
    if lock_until > now:
        return True, int((lock_until - now).total_seconds())
    return False, 0


def _count_consecutive_failures(db: Session, account: str) -> int:
    """统计锁定窗口内、自最近一次成功登录之后的连续失败次数。

    若窗口内出现过 success 记录，则计数从 success 之后重新开始；
    否则统计窗口内全部失败次数。
    """
    since = datetime.now() - timedelta(minutes=settings.LOGIN_LOCK_MINUTES)
    rows = db.scalars(
        select(LoginAudit)
        .where(
            LoginAudit.account == account,
            LoginAudit.created_at >= since,
        )
        .order_by(LoginAudit.created_at.asc())
    ).all()
    count = 0
    for r in rows:
        if r.result == "success":
            count = 0
        else:  # fail / locked
            count += 1
    return count


def record_login_failure(
    db: Session,
    account: str,
    user_id: int | None = None,
    ip: str | None = None,
    ua: str | None = None,
    reason: str | None = None,
) -> bool:
    """记录一次登录失败，达到阈值则写入锁定标记。

    Returns:
        是否触发账号锁定（True 表示本次失败使账号进入锁定状态）。
    """
    consecutive = _count_consecutive_failures(db, account)
    is_lock = (consecutive + 1) >= settings.LOGIN_MAX_FAILURES
    audit = LoginAudit(
        account=account,
        user_id=user_id,
        result="locked" if is_lock else "fail",
        failure_reason=reason,
        ip_address=ip,
        user_agent=ua,
        lock_triggered=1 if is_lock else 0,
    )
    db.add(audit)
    db.flush()
    return is_lock


def record_login_success(
    db: Session,
    account: str,
    user_id: int,
    ip: str | None = None,
    ua: str | None = None,
) -> None:
    """记录一次登录成功（用于审计与重置连续失败计数）。"""
    audit = LoginAudit(
        account=account,
        user_id=user_id,
        result="success",
        ip_address=ip,
        user_agent=ua,
        lock_triggered=0,
    )
    db.add(audit)
    db.flush()