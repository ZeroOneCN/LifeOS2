"""为 7 张高频表补充唯一约束

Revision ID: 3fd6b94691f3
Revises: 943429348ec7
Create Date: 2026-11-02 19:00:30.969133

本迁移只包含 7 条 `uq_` 前缀的唯一约束，不做任何索引增删、不改列类型/可空性/
默认值/注释，避免误改历史漂移（含 health_medication、finance_loan_bills 两张禁改表）。
执行前已对 7 张表做过重复检测，均为 0 组重复。
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3fd6b94691f3'
down_revision: Union[str, Sequence[str], None] = '943429348ec7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (约束名, 表名, 列名列表)
UNIQUE_CONSTRAINTS: list[tuple[str, str, list[str]]] = [
    ("uq_steps_user_date_period", "health_steps", ["user_id", "record_date", "period"]),
    ("uq_vitals_user_date", "health_vitals_sleep", ["user_id", "record_date"]),
    ("uq_medstock_user_name", "health_med_stock", ["user_id", "medicine_name"]),
    (
        "uq_util_user_house_month_type",
        "finance_utilities",
        ["user_id", "housing_id", "bill_month", "fee_type"],
    ),
    (
        "uq_rentterm_user_house_no",
        "finance_rent_terms",
        ["user_id", "housing_id", "term_no"],
    ),
    (
        "uq_cardbill_user_card_month",
        "lifestyle_card_bills",
        ["user_id", "phone_card_id", "bill_month"],
    ),
    ("uq_notif_user_source", "notifications", ["user_id", "source"]),
]


def upgrade() -> None:
    """逐条添加唯一约束。

    按 `UNIQUE_CONSTRAINTS` 顺序对每张表执行 `ALTER TABLE ... ADD CONSTRAINT`，
    依赖库中已有数据不冲突（执行前已做重复检测）。
    """
    for name, table, columns in UNIQUE_CONSTRAINTS:
        op.create_unique_constraint(name, table, columns)


def downgrade() -> None:
    """按相反顺序删除本次添加的唯一约束。

    只回滚本迁移新增的 7 条约束，不触碰其它结构。
    """
    for name, table, columns in reversed(UNIQUE_CONSTRAINTS):
        op.drop_constraint(name, table, type_="unique")
