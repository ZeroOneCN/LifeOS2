from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import (
    create_access_token,
    first_profile_or_create,
    get_current_user,
    hash_password,
    username_exists,
    verify_password,
)
from app.models import UserProfile
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UserMe

router = APIRouter(prefix="/auth", tags=["auth"])


def _build_token_response(profile: UserProfile) -> TokenResponse:
    """根据用户记录组装令牌响应（注册即登录）。"""
    return TokenResponse(
        access_token=create_access_token(profile.id, profile.username),
        user=UserMe.model_validate(profile),
    )


@router.post("/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    """注册账号。首个注册接管默认管理员记录（保留其个人资料数据），后续创建新账号。"""
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="用户名不能为空")
    if len(payload.password) < 6:
        raise HTTPException(status_code=400, detail="密码长度不能少于 6 位")

    default = first_profile_or_create(db)
    if not default.has_password:
        # 首注接管 id=1，仅写入登录凭证，不覆盖既有个人资料
        if username_exists(db, username, exclude_id=default.id):
            raise HTTPException(status_code=400, detail="用户名已被占用")
        default.username = username
        default.password_salt, default.password_hash = hash_password(payload.password)
        db.commit()
        db.refresh(default)
        return _build_token_response(default)

    if username_exists(db, username):
        raise HTTPException(status_code=400, detail="用户名已被占用")
    profile = UserProfile(
        username=username,
        nickname=payload.nickname or "未命名用户",
    )
    profile.password_salt, profile.password_hash = hash_password(payload.password)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return _build_token_response(profile)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    """账号密码登录。"""
    username = payload.username.strip()
    profile = db.scalar(
        select(UserProfile).where(UserProfile.username == username)
    )
    if not profile or not profile.has_password or not verify_password(
        payload.password,
        profile.password_salt or "",
        profile.password_hash,
    ):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    return _build_token_response(profile)


@router.get("/me", response_model=UserMe)
def me(user: UserProfile = Depends(get_current_user)):
    """获取当前登录用户信息。"""
    return user