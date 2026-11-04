"""创建定时任务执行状态表 scheduled_job_state

Revision ID: 8c4d2a1f7b90
Revises: 3fd6b94691f3
Create Date: 2026-11-04

本迁移为手写迁移，仅新增一张表；不使用 autogenerate，避免把 67 条历史漂移
带入迁移脚本，也不改动既有业务表。
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "8c4d2a1f7b90"
down_revision = "3fd6b94691f3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """创建 scheduled_job_state（每个定时任务一行最近执行状态）。"""
    op.create_table(
        "scheduled_job_state",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("job_name", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("error_summary", sa.String(length=255), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("job_name", name="uq_job_state_name"),
        mysql_charset="utf8mb4",
    )


def downgrade() -> None:
    """回滚：删除 scheduled_job_state（仅允许在临时空库演练使用）。"""
    op.drop_table("scheduled_job_state")
