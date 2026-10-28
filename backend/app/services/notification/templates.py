"""通知模板：默认模板定义、种子写入与渲染。"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.notification_center import NotificationTemplate


class _SafeDict(dict):
    """缺变量时返回空白，避免 KeyError。"""

    def __missing__(self, key):
        return ""


def render(template_title: str, template_content: str, ctx: dict) -> tuple[str, str]:
    """用上下文渲染标题与内容模板；缺失变量自动置空。"""
    safe = _SafeDict(ctx)
    try:
        title = template_title.format_map(safe)
    except Exception:
        title = template_title
    try:
        content = template_content.format_map(safe)
    except Exception:
        content = template_content
    return title, content


# (source, category, name, title模板, 内容模板, 说明)
DEFAULT_TEMPLATES: list[tuple[str, str, str, str, str, str]] = [
    (
        "finance_subscription_due",
        "财务",
        "服务订阅到期",
        "【服务订阅】{name} 即将到期",
        "订阅服务「{name}」（{category}）将于 {due_date} 到期，剩余 {days_left} 天。"
        "每期费用 {amount}，当前状态：{status}。",
        "服务订阅到期提醒",
    ),
    (
        "finance_utility_due",
        "财务",
        "水电燃气到期",
        "【水电燃气】{name} 待缴",
        "账单「{name}」（{fee_type}，{bill_month} 月）金额 {amount}，已于 {due_date} 到期，尚未缴纳。",
        "水电燃气/宽带待缴提醒",
    ),
    (
        "finance_loan_due",
        "财务",
        "网贷还款",
        "【网贷还款】{platform} {due_date} 应还",
        "平台「{platform}」{bill_month} 期账单金额 {amount}，应还日 {due_date}，剩余 {days_left} 天，"
        "已还 {paid_amount}，状态：{status}。{grace_tip}",
        "网贷/房贷还款提醒",
    ),
    (
        "finance_debt_due",
        "财务",
        "债务到期",
        "【债务到期】{name} {due_date}",
        "债务「{name}」（{direction}，对方 {counterparty}）到期日 {due_date}，剩余 {days_left} 天，"
        "总额 {amount}，剩余 {remaining}。",
        "借入/借出债务到期提醒",
    ),
    (
        "lifestyle_todo_due",
        "生活",
        "待办到期",
        "【待办到期】{title}",
        "待办「{title}」截止 {due_date}，剩余 {days_left} 天，优先级：{priority}。",
        "待办清单到期提醒",
    ),
    (
        "lifestyle_item_expire",
        "生活",
        "物品保质期",
        "【物品过期】{item_name} 即将过期",
        "物品「{item_name}」（分类 {category}）保质期截止 {expire_date}，剩余 {days_left} 天。",
        "物品保质期过期提醒",
    ),
    (
        "lifestyle_phone_bill",
        "生活",
        "手机卡月租扣账",
        "【手机卡月租】{phone_number} 待扣账",
        "手机卡 {phone_number}（{operator}）{bill_month} 月月租 {amount}，账单日 {bill_day}，本月尚未扣账。",
        "手机卡月租/扣账提醒",
    ),
    (
        "lifestyle_bankcard_due",
        "生活",
        "银行卡还款日",
        "【银行卡还款】{card_name} {due_date}",
        "银行卡「{card_name}」（{bank}）还款日 {due_date}，剩余 {days_left} 天，本期账单需关注及时还款。",
        "信用卡还款日提醒",
    ),
    (
        "health_med_stock",
        "健康",
        "药品低库存",
        "【药品低库存】{medicine_name}",
        "药品「{medicine_name}」当前库存 {stock}，低于阈值 {threshold}，请及时补货。",
        "药品库存不足提醒",
    ),
    (
        "health_checkup_due",
        "健康",
        "体检到期",
        "【体检到期】{next_date}",
        "您上次体检日期为 {last_date}，建议下次体检日期 {next_date}（剩余 {days_left} 天），请提前预约。",
        "年度体检到期提醒",
    ),
    (
        "lifestyle_card_expire",
        "生活",
        "银行卡有效期",
        "【银行卡有效期】{card_name} {expire_date}",
        "银行卡「{card_name}」（{bank}）有效期至 {expire_date}，{state}，请及时更新卡片信息。",
        "银行卡有效期到期提醒",
    ),
]


# 内置默认模板升级映射：source -> (旧值, 新值)，字段依次为 name / title_template / content_template。
# 仅当用户模板对应字段仍与旧内置值一致时才替换，用户自定义过的字段不受影响。
# 用于让已注册用户也同步获得重命名与改进后的文案。
LEGACY_DEFAULT_UPGRADES: dict[str, tuple[tuple[str, str, str], tuple[str, str, str]]] = {
    "finance_loan_due": (
        (
            "网贷还款",
            "【网贷还款】{platform} {due_date} 应还",
            "平台「{platform}」{bill_month} 期账单金额 {amount}，应还日 {due_date}，剩余 {days_left} 天，"
            "已还 {paid_amount}，状态：{status}。",
        ),
        (
            "网贷还款",
            "【网贷还款】{platform} {due_date} 应还",
            "平台「{platform}」{bill_month} 期账单金额 {amount}，应还日 {due_date}，剩余 {days_left} 天，"
            "已还 {paid_amount}，状态：{status}。{grace_tip}",
        ),
    ),
    "lifestyle_card_expire": (
        (
            "证件到期",
            "【证件到期】{card_name} {expire_date}",
            "银行卡「{card_name}」（{bank}）有效期至 {expire_date}，剩余 {days_left} 天，请及时联系银行换发新卡。",
        ),
        (
            "银行卡有效期",
            "【银行卡有效期】{card_name} {expire_date}",
            "银行卡「{card_name}」（{bank}）有效期至 {expire_date}，{state}，请及时更新卡片信息。",
        ),
    ),
}

_TEMPLATE_UPGRADE_FIELDS = ("name", "title_template", "content_template")


def upgrade_default_templates(db: Session, user_id: int) -> int:
    """将仍是旧内置默认值的模板字段升级为最新默认值。返回更新字段数。"""
    updated = 0
    for source, (old, new) in LEGACY_DEFAULT_UPGRADES.items():
        tpl = db.scalar(
            select(NotificationTemplate).where(
                NotificationTemplate.user_id == user_id,
                NotificationTemplate.source == source,
            )
        )
        if tpl is None:
            continue
        for attr, old_val, new_val in zip(_TEMPLATE_UPGRADE_FIELDS, old, new):
            if getattr(tpl, attr) == old_val:
                setattr(tpl, attr, new_val)
                updated += 1
    if updated:
        db.commit()
    return updated


def seed_templates(db: Session, user_id: int) -> int:
    """为指定用户补种内置默认模板：仅补齐该用户缺失的 source。

    按 source 逐个判断，保证后续版本新增的提醒场景也能补种给老用户，
    而不是整批跳过。
    """
    existing = set(
        db.scalars(
            select(NotificationTemplate.source).where(
                NotificationTemplate.user_id == user_id
            )
        ).all()
    )
    inserted = 0
    for source, category, name, title_tpl, content_tpl, note in DEFAULT_TEMPLATES:
        if source in existing:
            continue
        db.add(
            NotificationTemplate(
                user_id=user_id,
                source=source,
                category=category,
                name=name,
                title_template=title_tpl,
                content_template=content_tpl,
                is_default=True,
                note=note,
            )
        )
        inserted += 1
    if inserted:
        db.commit()
    return inserted


def get_default(source: str) -> tuple[str, str]:
    """根据 source 返回内置默认模板（标题模板, 内容模板）。"""
    for s, _c, _n, title_tpl, content_tpl, _note in DEFAULT_TEMPLATES:
        if s == source:
            return title_tpl, content_tpl
    return "【通知】", "通知内容：{content}"