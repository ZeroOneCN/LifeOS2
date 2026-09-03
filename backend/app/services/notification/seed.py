"""启动种子：为每个用户写入默认模板与功能提醒开关（已存在则该用户跳过）。

支持按 user_id 播种单个用户；不带 user_id 时为所有已存在的用户播种。
"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import UserProfile
from app.models.notification_center import (
    FeatureReminderSetting,
    NotificationTemplate,
)

from .templates import DEFAULT_TEMPLATES, seed_templates

# (feature_key, name, category, 默认开启)
DEFAULT_FEATURES: list[tuple[str, str, str, bool]] = [
    ("finance_subscription_due", "服务订阅到期", "财务", False),
    ("finance_utility_due", "水电燃气到期", "财务", False),
    ("finance_loan_due", "网贷/房贷还款", "财务", False),
    ("finance_reminder_due", "账单提醒事项", "财务", False),
    ("finance_debt_due", "债务到期", "财务", False),
    ("lifestyle_todo_due", "待办到期", "生活", False),
    ("lifestyle_item_expire", "物品保质期", "生活", False),
    ("lifestyle_phone_bill", "手机卡月租扣账", "生活", False),
    ("lifestyle_bankcard_due", "银行卡还款日", "生活", False),
    ("health_med_stock", "药品低库存", "健康", False),
]


def seed_feature_settings(db: Session, user_id: int) -> int:
    count = db.scalar(
        select(FeatureReminderSetting).where(
            FeatureReminderSetting.user_id == user_id
        ).limit(1)
    )
    if count is not None:
        return 0
    inserted = 0
    for key, name, category, enabled in DEFAULT_FEATURES:
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
    db.commit()
    return inserted


def _seed_user(db: Session, user_id: int) -> int:
    """为单个用户幂等播种模板与功能开关。返回插入总数。"""
    n_tpl = seed_templates(db, user_id)
    n_set = seed_feature_settings(db, user_id)
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