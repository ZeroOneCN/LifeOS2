from datetime import datetime

from pydantic import BaseModel


# ── 内置默认值（后端为唯一权威来源，读取时用于归一化空字段） ──────────────

DEFAULT_SITE_TITLE = "数字化生活助手"
DEFAULT_LOGIN_SUBTITLE = "使用你的账号登录以继续"
DEFAULT_REGISTER_SUBTITLE = "创建账号以使用数字化生活助手"

# 标题类字段长度上限（与数据库列长度保持一致）
MAX_TITLE_LEN = 64
MAX_SUBTITLE_LEN = 128


class SiteConfigRead(BaseModel):
    """品牌配置读取：所有字段均已归一化，不存在空值。"""

    site_title: str
    logo: str | None = None
    login_title: str
    login_subtitle: str
    register_title: str
    register_subtitle: str
    updated_at: datetime | None = None


class SiteConfigUpdate(BaseModel):
    """品牌配置局部更新：仅更新传入字段；传入空字符串表示回落内置默认值。"""

    site_title: str | None = None
    logo: str | None = None
    login_title: str | None = None
    login_subtitle: str | None = None
    register_title: str | None = None
    register_subtitle: str | None = None