from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class LoginAudit(Base):
    """登录安全审计：记录每一次登录尝试（成功/失败/锁定），用于追溯登录来源与暴力破解检测。

    与 UserSession 的区别：UserSession 只保存登录成功后下发的刷新令牌；
    LoginAudit 记录所有鉴权事件（含失败、账号不存在、账号锁定），用于安全审计。
    user_id 可为空：当账号本身不存在时无法关联到用户，仅记录原始账号字符串。
    """

    __tablename__ = "login_audits"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # 登录尝试时提交的账号（原样保留，即使账号不存在）
    account: Mapped[str] = mapped_column(String(64), index=True)
    # 关联到的真实用户（账号不存在时为 None）
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("user_profile.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # 登录结果：success / fail / locked
    result: Mapped[str] = mapped_column(String(16), index=True)
    # 失败原因：account_not_found / password_wrong / account_locked 等（成功时为 None）
    failure_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)
    # 来源 IP（X-Forwarded-For 取首个，回退到 client.host）
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    # 客户端 User-Agent（原样保留，最长 512）
    user_agent: Mapped[str | None] = mapped_column(String(512), nullable=True)
    # 本次失败是否触发了账号锁定（达到阈值那一次为 True）
    lock_triggered: Mapped[bool] = mapped_column(
        Integer, default=0
    )  # 用 Integer 承载布尔，兼容 MySQL 无原生 bool
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
