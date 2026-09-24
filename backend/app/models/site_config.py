from datetime import datetime

from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.dialects.mysql import MEDIUMTEXT
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class SiteConfig(Base):
    """系统品牌配置：全局单例（固定 id=1），存储 LOGO 与各页面标题。

    说明：登录/注册页处于未登录状态，配置需支持匿名读取，因此本表为全局单例，
    不按 user_id 归属；仅管理员账号可修改。
    """

    __tablename__ = "site_config"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # MEDIUMTEXT：base64 data URL 形式的 LOGO 体积可能超过 MySQL TEXT 的 64KB 上限
    logo: Mapped[str | None] = mapped_column(MEDIUMTEXT, nullable=True)  # LOGO（data URL）
    site_title: Mapped[str | None] = mapped_column(String(64), nullable=True)  # 系统标题
    login_title: Mapped[str | None] = mapped_column(String(64), nullable=True)  # 登录页标题
    login_subtitle: Mapped[str | None] = mapped_column(String(128), nullable=True)  # 登录页副标题
    register_title: Mapped[str | None] = mapped_column(String(64), nullable=True)  # 注册页标题
    register_subtitle: Mapped[str | None] = mapped_column(
        String(128), nullable=True
    )  # 注册页副标题
    updated_by: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 最后修改人 ID
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )