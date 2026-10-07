"""数据库复合索引补全：为高频查询字段(user_id + 日期/状态)创建复合索引。

项目未使用 Alembic，直接 create_all 不会为已存在的表补建索引。
此模块在启动时执行 CREATE INDEX IF NOT EXISTS，兼容新库与已有库。
"""

from sqlalchemy import text
from sqlalchemy.orm import Session

# (表名, 索引名, 字段列表)
COMPOSITE_INDEXES: list[tuple[str, str, list[str]]] = [
    ("health_steps", "ix_health_steps_user_date", ["user_id", "record_date"]),
    ("health_vitals_sleep", "ix_vitals_user_date", ["user_id", "record_date"]),
    ("health_medication", "ix_medication_user_date", ["user_id", "record_date"]),
    ("health_checkup", "ix_checkup_user_date", ["user_id", "check_date"]),
    ("finance_shopping_record", "ix_shopping_user_date", ["user_id", "record_date"]),
    ("finance_utility", "ix_utility_user_month", ["user_id", "bill_month"]),
    ("lifestyle_card_bill", "ix_cardbill_user_month", ["user_id", "bill_month"]),
    ("activity_logs", "ix_activity_user_created", ["user_id", "created_at"]),
    ("notifications", "ix_notif_user_date", ["user_id", "notify_date"]),
]


def ensure_composite_indexes(db: Session) -> int:
    """幂等创建复合索引，返回创建成功的数量。"""
    created = 0
    for table, idx_name, cols in COMPOSITE_INDEXES:
        col_sql = ", ".join(f'"{c}"' for c in cols)
        try:
            db.execute(
                text(
                    f'CREATE INDEX IF NOT EXISTS "{idx_name}" ON "{table}" ({col_sql})'
                )
            )
            created += 1
        except Exception:
            # 表不存在或字段不存在时跳过，不影响启动
            continue
    db.commit()
    return created
