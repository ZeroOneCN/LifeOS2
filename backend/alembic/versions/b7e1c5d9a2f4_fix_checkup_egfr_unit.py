"""修复体检 eGFR 单位被截断的历史数据

Revision ID: b7e1c5d9a2f4
Revises: 8c4d2a1f7b90
Create Date: 2026-11-26

旧系统导入时单位字段有长度限制，eGFR 被截成「mL/(min*1.」。这里只修数据、
不改表结构；当前列宽 32，完整单位可以正常保存。
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "b7e1c5d9a2f4"
down_revision = "8c4d2a1f7b90"
branch_labels = None
depends_on = None

_CORRECT_UNIT = "mL/(min*1.73m²)"


def upgrade() -> None:
    """把 eGFR 指标里残缺的单位补全为完整单位。"""
    op.execute(
        "UPDATE health_checkup SET unit = '{}' "
        "WHERE item_name LIKE '%eGFR%' AND unit LIKE 'mL/(min*1.%'".format(
            _CORRECT_UNIT
        )
    )
    op.execute(
        "UPDATE health_checkup_panel_item SET unit = '{}' "
        "WHERE item_name LIKE '%eGFR%' AND unit LIKE 'mL/(min*1.%'".format(
            _CORRECT_UNIT
        )
    )


def downgrade() -> None:
    """数据修复不回滚：恢复截断值没有意义。"""
    pass
