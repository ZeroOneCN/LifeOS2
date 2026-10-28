"""启动种子：为每个用户写入默认模板与功能提醒开关（已存在则该用户跳过）。

支持按 user_id 播种单个用户；不带 user_id 时为所有已存在的用户播种。
"""

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.models import UserProfile
from app.models.notification_center import (
    FeatureReminderSetting,
    NotificationTemplate,
)

from .templates import DEFAULT_TEMPLATES, seed_templates, upgrade_default_templates

# (feature_key, name, category, 默认开启)
DEFAULT_FEATURES: list[tuple[str, str, str, bool]] = [
    ("finance_subscription_due", "服务订阅到期", "财务", False),
    ("finance_utility_due", "水电燃气到期", "财务", False),
    ("finance_rent_due", "房租应缴", "财务", False),
    ("finance_loan_due", "网贷/房贷还款", "财务", False),
    ("finance_debt_due", "债务到期", "财务", False),
    ("lifestyle_item_expire", "物品保质期", "生活", False),
    ("lifestyle_phone_bill", "手机卡月租扣账", "生活", False),
    ("lifestyle_bankcard_due", "银行卡还款日", "生活", False),
    ("lifestyle_card_expire", "银行卡有效期", "生活", False),
    ("health_med_stock", "药品低库存", "健康", False),
    ("health_checkup_due", "体检到期", "健康", False),
]

# 历史内置功能名称 → 现名称：仅当仍为旧内置名称时更新（用户无法自定义名称），
# 使存量用户识别更直观。
LEGACY_FEATURE_RENAMES: dict[str, tuple[str, str]] = {
    "lifestyle_card_expire": ("证件到期", "银行卡有效期"),
}

# 已下线的提醒功能（如待办清单已从系统移除）：播种时清理其历史开关，避免留下无效控制项。
REMOVED_FEATURE_KEYS: tuple[str, ...] = ("lifestyle_todo_due",)


def seed_feature_settings(db: Session, user_id: int) -> int:
    """幂等补种功能提醒开关：补齐缺失的 feature_key，并同步旧内置名称。

    按 feature_key 逐个判断，保证后续版本新增的功能模块（如「银行卡有效期」）
    也能补种给已注册的老用户，而不是整批跳过。返回新增条数。
    """
    rows = {
        r.feature_key: r
        for r in db.scalars(
            select(FeatureReminderSetting).where(
                FeatureReminderSetting.user_id == user_id
            )
        ).all()
    }
    inserted = 0
    renamed = 0
    cleaned = db.execute(
        delete(FeatureReminderSetting).where(
            FeatureReminderSetting.user_id == user_id,
            FeatureReminderSetting.feature_key.in_(REMOVED_FEATURE_KEYS),
        )
    ).rowcount or 0
    for key, name, category, enabled in DEFAULT_FEATURES:
        row = rows.get(key)
        if row is None:
            db.add(
                FeatureReminderSetting(
                    user_id=user_id,
                    feature_key=key,
                    name=name,
                    category=category,
                    enabled=enabled,
                    advance_days=1,
                    channels="[]",
                )
            )
            inserted += 1
            continue
        legacy = LEGACY_FEATURE_RENAMES.get(key)
        if legacy and row.name == legacy[0]:
            row.name = legacy[1]
            renamed += 1
    if inserted or renamed or cleaned:
        db.commit()
    return inserted


def _seed_user(db: Session, user_id: int) -> int:
    """为单个用户幂等播种模板与功能开关。返回插入总数。"""
    n_tpl = seed_templates(db, user_id)
    n_set = seed_feature_settings(db, user_id)
    # 存量用户：将仍是旧内置默认文案的模板升级为新文案
    upgrade_default_templates(db, user_id)
    return n_tpl + n_set


def ensure_seed(db: Session, user_id: int | None = None) -> int:
    """幂等写入默认模板与功能开关。

    - user_id 指定时：仅播种该用户。
    - user_id 为空时：为所有已存在用户播种（向后兼容）。
    返回插入总条数。
    """
    if user_id is not None:
        return _seed_user(db, user_id)
    user_ids = db.scalars(select(UserProfile.id)).all()
    total = 0
    for uid in user_ids:
        total += _seed_user(db, uid)
    return total


def template_sources() -> list[str]:
    return [t[0] for t in DEFAULT_TEMPLATES]