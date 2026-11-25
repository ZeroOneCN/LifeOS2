"""修正白蛋白/球蛋白比值的错误单位

Revision ID: c8a4f1d2e6b7
Revises: b7e1c5d9a2f4
Create Date: 2026-11-26

「白蛋白/球蛋白」是比值，没有单位；历史数据里有一条被写成了 g/L，
会让用户误读。这里只清空该条记录的错误单位，不改表结构。
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "c8a4f1d2e6b7"
down_revision = "b7e1c5d9a2f4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """清空比值指标上误填的 g/L。"""
    op.execute(
        "UPDATE health_checkup SET unit = '' "
        "WHERE item_name = '白蛋白/球蛋白' AND unit = 'g/L'"
    )


def downgrade() -> None:
    """数据修复不回滚：恢复错误单位没有意义。"""
    pass
