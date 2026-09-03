from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user, hash_password, verify_password
from app.models import UserProfile
from app.schemas.user import (
    UserProfileRead,
    UserProfileUpdate,
    UserSettingsRead,
    UserSettingsUpdate,
)

router = APIRouter(prefix="/user", tags=["user"])


@router.get("/profile", response_model=UserProfileRead)
def get_profile(
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """获取当前登录用户的个人资料。"""
    return current_user


@router.put("/profile", response_model=UserProfileRead)
def update_profile(
    payload: UserProfileUpdate,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """更新当前登录用户的个人资料（仅更新传入的字段）。"""
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(current_user, key, value)
    db.commit()
    db.refresh(current_user)
    return current_user


@router.get("/settings", response_model=UserSettingsRead)
def get_settings(
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """获取当前登录用户的账号设置（用户名与密码状态）。"""
    return current_user


@router.put("/settings", response_model=UserSettingsRead)
def update_settings(
    payload: UserSettingsUpdate,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """更新当前登录用户的账号设置：可修改用户名；提供 new_password 时设置/修改密码。"""
    if payload.username is not None:
        username = payload.username.strip()
        if not username:
            raise HTTPException(status_code=400, detail="用户名不能为空")
        exists = db.scalar(
            select(UserProfile).where(
                UserProfile.username == username, UserProfile.id != current_user.id
            )
        )
        if exists:
            raise HTTPException(status_code=400, detail="用户名已被占用")
        current_user.username = username

    if payload.new_password:
        if len(payload.new_password) < 6:
            raise HTTPException(status_code=400, detail="新密码长度不能少于 6 位")
        if current_user.password_hash and not verify_password(
            payload.current_password or "",
            current_user.password_salt or "",
            current_user.password_hash,
        ):
            raise HTTPException(status_code=400, detail="当前密码错误")
        current_user.password_salt, current_user.password_hash = hash_password(
            payload.new_password
        )

    db.commit()
    db.refresh(current_user)
    return current_user
