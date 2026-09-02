import hashlib
import hmac
import secrets

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import UserProfile
from app.schemas.user import (
    UserProfileRead,
    UserProfileUpdate,
    UserSettingsRead,
    UserSettingsUpdate,
)

router = APIRouter(prefix="/user", tags=["user"])


def _hash_password(password: str) -> tuple[str, str]:
    """生成 (盐, 哈希)，使用 PBKDF2-SHA256。"""
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), bytes.fromhex(salt), 100_000
    ).hex()
    return salt, digest


def _verify_password(password: str, salt: str, digest: str) -> bool:
    """校验密码是否匹配。"""
    check = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), bytes.fromhex(salt), 100_000
    ).hex()
    return hmac.compare_digest(check, digest)


def _get_or_create(db: Session) -> UserProfile:
    """获取当前用户资料；若无则创建默认记录。"""
    profile = db.scalar(select(UserProfile).order_by(UserProfile.id).limit(1))
    if not profile:
        profile = UserProfile(nickname="未命名用户")
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile


@router.get("/profile", response_model=UserProfileRead)
def get_profile(db: Session = Depends(get_db)):
    """获取个人资料，首次访问自动创建默认资料。"""
    return _get_or_create(db)


@router.put("/profile", response_model=UserProfileRead)
def update_profile(payload: UserProfileUpdate, db: Session = Depends(get_db)):
    """更新个人资料（仅更新传入的字段）。"""
    profile = _get_or_create(db)
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(profile, key, value)
    db.commit()
    db.refresh(profile)
    return profile


@router.get("/settings", response_model=UserSettingsRead)
def get_settings(db: Session = Depends(get_db)):
    """获取账号设置（用户名与密码状态）。"""
    return _get_or_create(db)


@router.put("/settings", response_model=UserSettingsRead)
def update_settings(payload: UserSettingsUpdate, db: Session = Depends(get_db)):
    """更新账号设置：可修改用户名；提供 new_password 时设置/修改密码。"""
    profile = _get_or_create(db)

    if payload.username is not None:
        username = payload.username.strip()
        if not username:
            raise HTTPException(status_code=400, detail="用户名不能为空")
        exists = db.scalar(
            select(UserProfile).where(
                UserProfile.username == username, UserProfile.id != profile.id
            )
        )
        if exists:
            raise HTTPException(status_code=400, detail="用户名已被占用")
        profile.username = username

    if payload.new_password:
        if len(payload.new_password) < 6:
            raise HTTPException(status_code=400, detail="新密码长度不能少于 6 位")
        if profile.password_hash and not _verify_password(
            payload.current_password or "",
            profile.password_salt or "",
            profile.password_hash,
        ):
            raise HTTPException(status_code=400, detail="当前密码错误")
        profile.password_salt, profile.password_hash = _hash_password(payload.new_password)

    db.commit()
    db.refresh(profile)
    return profile
