from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import UserProfile
from app.schemas.user import UserProfileRead, UserProfileUpdate

router = APIRouter(prefix="/user", tags=["user"])


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
