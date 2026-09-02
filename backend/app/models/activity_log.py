from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class ActivityLog(Base):
    """活动日志：通过中间件自动记录各模块的新增/更新/删除操作。"""

    __tablename__ = "activity_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    action: Mapped[str] = mapped_column(String(16), index=True)  # create/update/delete
    module: Mapped[str] = mapped_column(String(64), index=True)  # 所属模块路径，如 health/steps
    resource_type: Mapped[str] = mapped_column(String(64))  # 资源类型（末段路径）
    resource_id: Mapped[int | None] = mapped_column(Integer)  # 资源ID
    summary: Mapped[str | None] = mapped_column(String(255))  # 中文操作摘要
    detail: Mapped[str | None] = mapped_column(Text)  # 操作详情（请求/响应内容）
    ip: Mapped[str | None] = mapped_column(String(45))  # 来源IP
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), index=True
    )
