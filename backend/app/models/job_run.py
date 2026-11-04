"""定时任务执行状态：每个 job 一行，记录最近一次执行结果。"""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class ScheduledJobState(Base):
    """定时任务最近一次执行状态（跨进程共享，供健康检查与排障读取）。

    每个 job 只保留一行，由 ``run_job`` 在每次执行后更新；不保存堆栈，
    ``error_summary`` 仅保留截断后的错误摘要。
    """

    __tablename__ = "scheduled_job_state"
    __table_args__ = (
        UniqueConstraint("job_name", name="uq_job_state_name"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_name: Mapped[str] = mapped_column(String(64))  # 任务唯一名，如 backup_scheduled_scan
    status: Mapped[str] = mapped_column(String(16))  # success / failed / skipped
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 本次耗时（毫秒）
    error_summary: Mapped[str | None] = mapped_column(String(255), nullable=True)  # 截断后的错误摘要
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )
