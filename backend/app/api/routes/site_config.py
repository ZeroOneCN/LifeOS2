"""系统品牌配置路由：LOGO 与各页面标题的读取 / 更新 / 恢复默认。

读取接口匿名开放（登录页、注册页在未登录状态下需展示品牌信息），
写入接口仅管理员账号可用。
"""

import base64
import re

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_admin
from app.models import UserProfile
from app.models.site_config import SiteConfig
from app.schemas.site_config import (
    DEFAULT_LOGIN_SUBTITLE,
    DEFAULT_REGISTER_SUBTITLE,
    DEFAULT_SITE_TITLE,
    MAX_SUBTITLE_LEN,
    MAX_TITLE_LEN,
    SiteConfigRead,
    SiteConfigUpdate,
)

router = APIRouter(prefix="/site-config", tags=["site-config"])

# 全局单例行固定 ID
CONFIG_ID = 1

# LOGO 仅接受 data URL 形式的图片
LOGO_PATTERN = re.compile(
    r"^data:image/(png|jpeg|jpg|webp|svg\+xml);base64,[A-Za-z0-9+/]+={0,2}$"
)
# data URL 字符串长度上限（约对应 200KB 原图）
MAX_LOGO_DATA_LEN = 300 * 1024
# SVG 不安全内容黑名单：脚本标签、javascript 协议、内联事件属性
SVG_UNSAFE_PATTERN = re.compile(r"<script|javascript:|on[a-z]+\s*=", re.IGNORECASE)

# 可写字段及其长度上限（None 表示 logo，长度另由 MAX_LOGO_DATA_LEN 控制）
TEXT_LIMITS: dict[str, int] = {
    "site_title": MAX_TITLE_LEN,
    "login_title": MAX_TITLE_LEN,
    "login_subtitle": MAX_SUBTITLE_LEN,
    "register_title": MAX_TITLE_LEN,
    "register_subtitle": MAX_SUBTITLE_LEN,
}


def _get_config(db: Session) -> SiteConfig | None:
    """读取全局品牌配置行，不存在时返回 None（不在读接口内建行）。"""
    return db.get(SiteConfig, CONFIG_ID)


def _to_read(row: SiteConfig | None) -> SiteConfigRead:
    """将配置行归一化为响应模型：空字段回落内置默认值。

    标题类默认值由系统标题派生，保证只改「系统标题」时登录/注册页文案同步跟随。

    Args:
        row: 数据库配置行，可能为 None（尚未配置过）。

    Returns:
        SiteConfigRead: 已归一化的品牌配置。
    """
    site_title = (row.site_title if row else None) or DEFAULT_SITE_TITLE
    return SiteConfigRead(
        site_title=site_title,
        logo=(row.logo if row else None) or None,
        login_title=(row.login_title if row else None) or f"登录 {site_title}",
        login_subtitle=(row.login_subtitle if row else None) or DEFAULT_LOGIN_SUBTITLE,
        register_title=(row.register_title if row else None) or f"注册 {site_title}",
        register_subtitle=(row.register_subtitle if row else None)
        or DEFAULT_REGISTER_SUBTITLE,
        updated_at=row.updated_at if row else None,
    )


def _validate_logo(value: str) -> str:
    """校验 LOGO 的 data URL 格式、体积与 SVG 安全性。

    Args:
        value: 前端 FileReader 生成的 data URL。

    Returns:
        str: 校验通过的原始 data URL。

    Raises:
        HTTPException: 格式不支持 / 体积超限 / SVG 含不安全内容时返回 400。
    """
    if not LOGO_PATTERN.match(value):
        raise HTTPException(
            status_code=400, detail="LOGO 格式不支持，仅支持 PNG / JPEG / WEBP / SVG 图片"
        )
    if len(value) > MAX_LOGO_DATA_LEN:
        raise HTTPException(status_code=400, detail="LOGO 体积过大，请压缩到 200KB 以内")

    mime, _, payload = value.partition(";base64,")
    if mime.endswith("svg+xml"):
        try:
            text = base64.b64decode(payload).decode("utf-8", "ignore")
        except (ValueError, TypeError):
            raise HTTPException(status_code=400, detail="LOGO 文件解析失败，请重新上传")
        if SVG_UNSAFE_PATTERN.search(text):
            raise HTTPException(
                status_code=400, detail="SVG 中包含不安全内容，请改用 PNG 格式上传"
            )
    return value


def _normalize_text(field: str, value: str | None) -> str | None:
    """将文本字段去空格并校验长度，空字符串统一转为 None（表示回落默认值）。"""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    limit = TEXT_LIMITS[field]
    if len(text) > limit:
        raise HTTPException(status_code=400, detail=f"内容过长，最多 {limit} 个字符")
    return text


@router.get("", response_model=SiteConfigRead)
def get_site_config(db: Session = Depends(get_db)):
    """获取系统品牌配置（匿名可读，供全站与登录/注册页使用）。"""
    return _to_read(_get_config(db))


@router.put("", response_model=SiteConfigRead)
def update_site_config(
    payload: SiteConfigUpdate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_admin),
):
    """更新系统品牌配置（仅管理员）：仅更新传入字段，空字符串表示恢复该项默认值。"""
    row = _get_config(db)
    if row is None:
        row = SiteConfig(id=CONFIG_ID)
        db.add(row)

    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        if field == "logo":
            row.logo = _validate_logo(value) if value else None
        else:
            setattr(row, field, _normalize_text(field, value))

    row.updated_by = user.id
    db.commit()
    db.refresh(row)
    return _to_read(row)


@router.post("/reset", response_model=SiteConfigRead)
def reset_site_config(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_admin),
):
    """恢复系统品牌配置为内置默认值（仅管理员）：清空全部自定义字段。"""
    row = _get_config(db)
    if row is None:
        return _to_read(None)

    row.logo = None
    for field in TEXT_LIMITS:
        setattr(row, field, None)
    row.updated_by = user.id
    db.commit()
    db.refresh(row)
    return _to_read(row)