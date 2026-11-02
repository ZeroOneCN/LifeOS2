"""数据库复合索引补全：为高频查询字段(user_id + 日期/状态)创建复合索引。

项目未使用 Alembic，直接 create_all 不会为已存在的表补建索引。
此模块在启动时先查 information_schema.statistics 判断索引是否存在，再执行
MySQL 合法 DDL（MySQL 不支持 CREATE INDEX IF NOT EXISTS，双引号也不是标识符）。
"""

import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

LOGGER = logging.getLogger(__name__)

# (表名, 索引名, 字段列表)
COMPOSITE_INDEXES: list[tuple[str, str, list[str]]] = [
    ("health_steps", "ix_health_steps_user_date", ["user_id", "record_date"]),
    ("health_vitals_sleep", "ix_vitals_user_date", ["user_id", "record_date"]),
    ("health_medication", "ix_medication_user_date", ["user_id", "record_date"]),
    ("health_checkup", "ix_checkup_user_date", ["user_id", "check_date"]),
    ("finance_shopping_records", "ix_shopping_user_date", ["user_id", "record_date"]),
    ("finance_utilities", "ix_utility_user_month", ["user_id", "bill_month"]),
    ("lifestyle_card_bills", "ix_cardbill_user_month", ["user_id", "bill_month"]),
    ("activity_logs", "ix_activity_user_created", ["user_id", "created_at"]),
    ("notifications", "ix_notif_user_date", ["user_id", "notify_date"]),
    ("login_audits", "ix_loginaudit_account_created", ["account", "created_at"]),
    ("login_audits", "ix_loginaudit_ip_created", ["ip_address", "created_at"]),
]


def _index_exists(db: Session, table: str, index_name: str) -> bool:
    """通过 information_schema.statistics 判断指定表的索引是否已存在。

    Args:
        db: 数据库会话。
        table: 表名。
        index_name: 索引名。

    Returns:
        索引已存在返回 True，否则返回 False。
    """
    row = db.execute(
        text(
            "SELECT 1 FROM information_schema.statistics "
            "WHERE table_schema = DATABASE() "
            "AND table_name = :table_name "
            "AND index_name = :index_name LIMIT 1"
        ),
        {"table_name": table, "index_name": index_name},
    ).first()
    return row is not None


def ensure_composite_indexes(db: Session) -> int:
    """幂等创建复合索引，返回本次新建成功的数量。

    先提交已挂起的事务（如 seed 数据），再逐条判断索引是否存在后创建；
    单条创建失败只记录 warning 并继续，不再静默吞掉异常。

    Args:
        db: 数据库会话。

    Returns:
        本次实际新建的索引数量。
    """
    db.commit()  # 避免与调用方挂起的 seed 事务混在一起
    created = 0
    for table, idx_name, cols in COMPOSITE_INDEXES:
        try:
            if _index_exists(db, table, idx_name):
                continue
            col_sql = ", ".join(f"`{c}`" for c in cols)
            db.execute(text(f"CREATE INDEX `{idx_name}` ON `{table}` ({col_sql})"))
            created += 1
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("创建复合索引 %s ON %s 失败：%s", idx_name, table, exc)
            db.rollback()
    db.commit()
    return created
