"""表名中文映射守卫：新增表漏配中文名时直接让测试失败。

映射唯一真源为 ``app.services.backup_service.TABLE_LABELS``，备份接口
``/backup/tables`` 直接消费它，前端不再维护第二份映射，因此这里同时校验
「模型表不能漏」与「映射不能指向已不存在的表」两个方向。
"""

import re

import app.models  # noqa: F401  确保全部模型注册到 Base.metadata
from app.core.database import Base
from app.services.backup_service import TABLE_LABELS

# 至少要包含一个中日韩统一表意文字，避免用英文占位冒充中文名
_CJK_PATTERN = re.compile(r"[\u4e00-\u9fff]")


def test_all_model_tables_have_label() -> None:
    """Base.metadata 中的每张表都必须登记中文名，缺失时打印完整清单。"""
    missing = sorted(name for name in Base.metadata.tables if name not in TABLE_LABELS)
    assert not missing, (
        "以下数据表缺少中文名映射，请在 app/services/backup_service.py 的 TABLE_LABELS 中登记：\n"
        + "\n".join(f"  - {name}" for name in missing)
    )


def test_labels_are_chinese() -> None:
    """映射值必须是非空且包含中文的短名称，避免空白或英文占位。"""
    invalid = sorted(
        name
        for name, label in TABLE_LABELS.items()
        if not label.strip() or not _CJK_PATTERN.search(label)
    )
    assert not invalid, "以下数据表的中文名不是有效中文（空值或英文占位）：\n" + "\n".join(
        f"  - {name}: {TABLE_LABELS[name]!r}" for name in invalid
    )


def test_no_dead_label_keys() -> None:
    """映射里不允许出现指向已删除表的死键，保持真源与模型一致。"""
    dead = sorted(name for name in TABLE_LABELS if name not in Base.metadata.tables)
    assert not dead, (
        "以下中文名映射指向了不存在的表，请删除这些死键：\n"
        + "\n".join(f"  - {name}: {TABLE_LABELS[name]}" for name in dead)
    )
