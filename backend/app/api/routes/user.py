from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_user, hash_password, verify_password
from app.models import UserProfile
from app.schemas.user import (
    UserAvatarRead,
    UserAvatarUrlUpdate,
    UserProfileRead,
    UserProfileUpdate,
    UserSettingsRead,
    UserSettingsUpdate,
)
from app.services.avatar_storage import (
    delete_local_avatar,
    save_avatar_file,
    validate_avatar_url,
    validate_image_upload,
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
    """更新当前登录用户的个人资料（仅更新传入的字段）。

    兼容旧调用：仍可通过 avatar 字段直接设置头像；若旧头像是本站上传文件，
    替换后同步清理旧文件，避免残留。
    """
    old_avatar = current_user.avatar
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(current_user, key, value)
    db.commit()
    if "avatar" in payload.model_fields_set and current_user.avatar != old_avatar:
        delete_local_avatar(old_avatar)
    db.refresh(current_user)
    return current_user


def _read_upload_limited(file: UploadFile, limit: int) -> bytes:
    """分块读取上传文件，累计超过上限立即中断，避免大文件占满内存。

    Args:
        file: 上传的图片文件对象。
        limit: 允许的最大字节数。

    Returns:
        文件完整二进制内容。

    Raises:
        HTTPException: 大小为 0 或超过 limit 时返回 400 / 413。
    """
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = file.file.read(64 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise HTTPException(
                status_code=413,
                detail=f"头像图片不能超过 {limit / (1024 * 1024):g} MB",
            )
        chunks.append(chunk)
    content = b"".join(chunks)
    if not content:
        raise HTTPException(status_code=400, detail="上传的图片内容为空")
    return content


@router.post("/avatar", response_model=UserAvatarRead)
def upload_avatar(
    file: UploadFile = File(...),
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """上传头像图片：multipart/form-data，字段名 file，单张不超过 2 MB。

    落盘使用不可猜测的随机文件名，数据库只保存相对访问路径；
    替换成功后清理旧的本站文件，外链旧头像不受影响。
    """
    content = _read_upload_limited(file, settings.AVATAR_MAX_BYTES)
    try:
        ext = validate_image_upload(file.filename, content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    old_avatar = current_user.avatar
    new_avatar = save_avatar_file(content, ext)
    current_user.avatar = new_avatar
    try:
        db.commit()
    except Exception:  # noqa: BLE001 - 写入失败需清理刚落盘的新文件
        db.rollback()
        delete_local_avatar(new_avatar)
        raise
    delete_local_avatar(old_avatar)
    db.refresh(current_user)
    return {"avatar": new_avatar}


@router.put("/avatar", response_model=UserAvatarRead)
def update_avatar_url(
    payload: UserAvatarUrlUpdate,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """使用图片地址设置头像（JSON）；avatar_url 为 null 时清空头像。

    外链只保存地址本身；若旧头像是本站上传文件，切换后同步清理旧文件。
    """
    new_avatar: str | None = None
    if payload.avatar_url is not None:
        try:
            new_avatar = validate_avatar_url(payload.avatar_url)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    old_avatar = current_user.avatar
    current_user.avatar = new_avatar
    db.commit()
    delete_local_avatar(old_avatar)
    db.refresh(current_user)
    return {"avatar": new_avatar}


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
