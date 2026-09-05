from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models.mixins import UserOwned


class ScheduledBackup(UserOwned, Base):
    """定时备份计划：按 cron 表达式自动执行数据导出。"""

    __tablename__ = "scheduled_backups"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    name: Mapped[str] = mapped_column(String(64))  # 任务名称
    cron_expression: Mapped[str] = mapped_column(String(32))  # 5-field cron, e.g. "0 3 * * *"
    export_format: Mapped[str] = mapped_column(String(8), default="json")  # json / sql
    compress: Mapped[bool] = mapped_column(Boolean, default=False)  # 仅 JSON 有效
    table_selection: Mapped[str] = mapped_column(String(16), default="all")  # all / selected
    selected_tables: Mapped[str | None] = mapped_column(Text)  # JSON 数组，仅 table_selection=selected 时
    last_run_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_status: Mapped[str | None] = mapped_column(String(16), nullable=True)  # success / failed
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )


class BackupLog(UserOwned, Base):
    """备份执行日志：记录每次自动/手动备份的详细结果。"""

    __tablename__ = "backup_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    schedule_id: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 关联的定时任务 ID，手动导出为 null
    name: Mapped[str] = mapped_column(String(64))  # 任务名称 / 导出名称
    export_format: Mapped[str] = mapped_column(String(8))  # json / sql
    filename: Mapped[str | None] = mapped_column(String(128), nullable=True)  # 生成的文件名
    file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 文件大小（字节）
    status: Mapped[str] = mapped_column(String(16))  # success / failed
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)  # 失败时的错误信息
    started_at: Mapped[datetime] = mapped_column(DateTime)
    finished_at: Mapped[datetime] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())