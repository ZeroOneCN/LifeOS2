"""启动种子：写入默认模板与功能提醒开关（表为空时）。"""

from sqlalchemy import select
from sqlalchemy.orm import Session

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


def seed_feature_settings(db: Session) -> int:
    count = db.scalar(select(FeatureReminderSetting).limit(1))
    if count is not None:
        return 0
    inserted = 0
    for key, name, category, enabled in DEFAULT_FEATURES:
        db.add(
            FeatureReminderSetting(
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


def ensure_seed(db: Session) -> None:
    """幂等写入默认模板（若表空）与功能开关（若表空）。"""
    seed_templates(db)
    seed_feature_settings(db)


def template_sources() -> list[str]:
    return [t[0] for t in DEFAULT_TEMPLATES]