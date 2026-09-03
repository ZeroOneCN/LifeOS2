from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import (
    account_exists,
    create_access_token,
    get_current_user,
    hash_password,
    username_exists,
    verify_password,
)
from app.models import UserProfile
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UserMe
from app.services.notification.seed import ensure_seed

router = APIRouter(prefix="/auth", tags=["auth"])


def _build_token_response(profile: UserProfile) -> TokenResponse:
    """根据用户记录组装令牌响应（注册即登录）。"""
    return TokenResponse(
        access_token=create_access_token(profile.id, profile.username),
        user=UserMe.model_validate(profile),
    )


@router.post("/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
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
        nickname=payload.nickname or "未命名用户",
        is_admin=is_first,
    )
    profile.password_salt, profile.password_hash = hash_password(payload.password)
    db.add(profile)
    db.commit()
    db.refresh(profile)

    # 为新用户预置通知模板与功能提醒开关
    ensure_seed(db, profile.id)
    db.commit()

    return _build_token_response(profile)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    """账号密码登录。"""
    account = payload.account.strip()
    profile = db.scalar(
        select(UserProfile).where(UserProfile.account == account)
    )
    if not profile or not profile.has_password or not verify_password(
        payload.password,
        profile.password_salt or "",
        profile.password_hash,
    ):
        raise HTTPException(status_code=401, detail="账号或密码错误")
    return _build_token_response(profile)


@router.get("/me", response_model=UserMe)
def me(user: UserProfile = Depends(get_current_user)):
    """获取当前登录用户信息。"""
    return user