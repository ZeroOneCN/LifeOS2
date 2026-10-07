from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class UserSession(Base):
    """用户会话（刷新令牌）：用于 JWT 刷新与会话管理（查看在线设备、强制下线）。"""

    __tablename__ = "user_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("user_profile.id", ondelete="CASCADE"), index=True)
    # 刷新令牌的哈希（不存明文，泄露后无法直接使用）
    refresh_token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    # 设备/浏览器标识（可选，来自 User-Agent 摘要）
    device: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # 登录 IP（可选）
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    last_used_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )
