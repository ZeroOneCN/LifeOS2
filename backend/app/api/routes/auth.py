from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import (
    _is_locked,
    account_exists,
    clear_login_failures,
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
    hash_password,
    hash_refresh_token,
    record_login_failure,
    username_exists,
    verify_password,
)
from app.models import UserProfile, UserSession
from app.schemas.auth import (
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenRefreshResponse,
    TokenResponse,
    UserMe,
)
from app.services.notification.seed import ensure_seed

router = APIRouter(prefix="/auth", tags=["auth"])


def _create_session(
    db: Session, user_id: int, refresh_token: str, device: str | None = None, ip: str | None = None
) -> UserSession:
    """创建用户会话记录（存储刷新令牌哈希）。"""
    session = UserSession(
        user_id=user_id,
        refresh_token_hash=hash_refresh_token(refresh_token),
        device=device,
        ip_address=ip,
        expires_at=datetime.now(timezone.utc)
        + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    db.add(session)
    return session


def _build_token_response(
    profile: UserProfile, db: Session, device: str | None = None, ip: str | None = None
) -> TokenResponse:
    """根据用户记录组装令牌响应（注册即登录），并创建会话记录。"""
    access = create_access_token(profile.id, profile.username)
    refresh = create_refresh_token(profile.id)
    _create_session(db, profile.id, refresh, device, ip)
    db.commit()
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        user=UserMe.model_validate(profile),
    )


@router.post("/register", response_model=TokenResponse)
def register(
    payload: RegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """注册账号。首个注册用户自动成为管理员。"""
    account = payload.account.strip()
    if not account:
        raise HTTPException(status_code=400, detail="账号不能为空")
    if len(payload.password) < 6:
        raise HTTPException(status_code=400, detail="密码长度不能少于 6 位")
    if account_exists(db, account):
        raise HTTPException(status_code=400, detail="账号已被占用")
    if payload.username and username_exists(db, payload.username.strip()):
        raise HTTPException(status_code=400, detail="用户名已被占用")

    is_first = (
        db.scalar(select(func.count()).select_from(UserProfile)) or 0
    ) == 0
    profile = UserProfile(
        account=account,
        username=payload.username.strip() if payload.username else account,
        nickname=payload.nickname.strip()
        if payload.nickname
        else (payload.username.strip() if payload.username else "未命名用户"),
        is_admin=is_first,
    )
    profile.password_salt, profile.password_hash = hash_password(payload.password)
    db.add(profile)
    db.commit()
    db.refresh(profile)

    # 为新用户预置通知模板与功能提醒开关
    ensure_seed(db, profile.id)
    db.commit()

    return _build_token_response(profile, db, request.headers.get("user-agent"), request.client.host if request.client else None)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """账号密码登录；连续失败 5 次后锁定 15 分钟。"""
    account = payload.account.strip()

    locked, remaining = _is_locked(account)
    if locked:
        raise HTTPException(
            status_code=429,
            detail=f"账号已被临时锁定，请 {remaining // 60} 分钟后再试",
        )

    profile = db.scalar(
        select(UserProfile).where(UserProfile.account == account)
    )
    if not profile or not profile.has_password or not verify_password(
        payload.password,
        profile.password_salt or "",
        profile.password_hash,
    ):
        record_login_failure(account)
        locked, remaining = _is_locked(account)
        if locked:
            raise HTTPException(
                status_code=429,
                detail=f"连续登录失败次数过多，账号已锁定 {remaining // 60} 分钟",
            )
        raise HTTPException(status_code=401, detail="账号或密码错误")

    clear_login_failures(account)
    return _build_token_response(
        profile, db, request.headers.get("user-agent"), request.client.host if request.client else None
    )


@router.post("/refresh", response_model=TokenRefreshResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    """使用刷新令牌换取新的访问令牌。"""
    token_payload = decode_token(payload.refresh_token)
    if token_payload is None or token_payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="刷新令牌无效或已过期")

    token_hash = hash_refresh_token(payload.refresh_token)
    session = db.scalar(
        select(UserSession).where(UserSession.refresh_token_hash == token_hash)
    )
    if session is None or session.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=401, detail="刷新令牌无效或已过期")

    user_id = int(token_payload["sub"])
    profile = db.get(UserProfile, user_id)
    if profile is None:
        raise HTTPException(status_code=401, detail="用户不存在")

    # 刷新成功后更新会话最后使用时间
    session.last_used_at = datetime.now(timezone.utc)
    db.commit()

    return TokenRefreshResponse(
        access_token=create_access_token(profile.id, profile.username)
    )


@router.post("/logout", status_code=204)
def logout(payload: RefreshRequest, db: Session = Depends(get_db)):
    """注销：删除当前刷新令牌对应的会话记录。"""
    token_hash = hash_refresh_token(payload.refresh_token)
    db.execute(
        delete(UserSession).where(UserSession.refresh_token_hash == token_hash)
    )
    db.commit()
    return None


@router.get("/me", response_model=UserMe)
def me(user: UserProfile = Depends(get_current_user)):
    """获取当前登录用户信息。"""
    return user


@router.get("/sessions")
def list_sessions(
    current_token: str | None = None,
    user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """列出当前用户的所有活跃会话（用于会话管理 / 强制下线）。

    传入 current_token（refresh_token）时，会标记与该令牌匹配的会话为当前设备。
    """
    sessions = db.scalars(
        select(UserSession)
        .where(UserSession.user_id == user.id)
        .order_by(UserSession.last_used_at.desc())
    ).all()
    current_hash = hash_refresh_token(current_token) if current_token else None
    return [
        {
            "id": s.id,
            "device": s.device,
            "ip_address": s.ip_address,
            "created_at": s.created_at.isoformat(),
            "last_used_at": s.last_used_at.isoformat(),
            "expires_at": s.expires_at.isoformat(),
            "is_current": current_hash is not None and s.refresh_token_hash == current_hash,
        }
        for s in sessions
    ]


@router.delete("/sessions/{session_id}", status_code=204)
def revoke_session(
    session_id: int,
    user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """强制下线指定会话（删除其刷新令牌）。"""
    session = db.scalar(
        select(UserSession).where(
            UserSession.id == session_id, UserSession.user_id == user.id
        )
    )
    if session is None:
        raise HTTPException(status_code=404, detail="会话不存在")
    db.delete(session)
    db.commit()
    return None


@router.post("/sessions/revoke-others", status_code=204)
def revoke_other_sessions(
    payload: RefreshRequest,
    user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """下线除当前会话外的所有其他会话。"""
    current_hash = hash_refresh_token(payload.refresh_token)
    db.execute(
        delete(UserSession).where(
            UserSession.user_id == user.id,
            UserSession.refresh_token_hash != current_hash,
        )
    )
    db.commit()
    return None
