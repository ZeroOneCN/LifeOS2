from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class TimestampMixin:
    """公共时间戳字段。"""

    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )


class LifestyleItem(TimestampMixin, Base):
    """物品追踪：个人物品管理，支持从购物记录同步及使用时长/费用分摊分析。"""

    __tablename__ = "lifestyle_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_name: Mapped[str] = mapped_column(String(128), index=True)  # 物品名称
    category: Mapped[str] = mapped_column(String(32), index=True)  # 分类
    location: Mapped[str | None] = mapped_column(String(64))  # 存放位置
    status: Mapped[str] = mapped_column(
        String(16), default="in_use"
    )  # in_use/lost/loaned/recycled
    purchase_date: Mapped[date | None] = mapped_column(Date)  # 购买日期
    price: Mapped[float | None] = mapped_column(Float)  # 价格
    expire_date: Mapped[date | None] = mapped_column(Date)  # 过期时间（保质期截止）
    end_date: Mapped[date | None] = mapped_column(Date)  # 使用结束/淘汰日期（用于计已用时长）
    source: Mapped[str] = mapped_column(
        String(16), default="manual"
    )  # manual/shopping 来源
    shopping_record_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 关联购物记录
    note: Mapped[str | None] = mapped_column(Text)


class LifestylePhoneCard(TimestampMixin, Base):
    """卡片管理-手机号卡：手机号、运营商、资费与扣账账单。"""

    __tablename__ = "lifestyle_phone_cards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    phone_number: Mapped[str] = mapped_column(String(32), unique=True, index=True)  # 号码
    operator: Mapped[str] = mapped_column(String(32), index=True)  # 运营商
    region: Mapped[str | None] = mapped_column(String(32))  # 归属地
    balance: Mapped[float | None] = mapped_column(Float, default=0)  # 余额
    monthly_fee: Mapped[float | None] = mapped_column(Float, default=0)  # 月租
    bill_day: Mapped[int | None] = mapped_column(Integer)  # 账单日
    data_plan: Mapped[str | None] = mapped_column(String(64))  # 流量套餐
    call_plan: Mapped[str | None] = mapped_column(String(64))  # 通话
    sms_plan: Mapped[str | None] = mapped_column(String(64))  # 短信
    open_date: Mapped[date | None] = mapped_column(Date)  # 开卡时间
    billing_type: Mapped[str] = mapped_column(
        String(16), default="monthly"
    )  # monthly/one_time/yearly 按月/一次性/按年保号
    bill_paid_this_month: Mapped[bool] = mapped_column(Boolean, default=False)  # 本月是否已扣账
    status: Mapped[str] = mapped_column(
        String(16), default="active"
    )  # active/frozen/expired/disabled 正常/冻结/已过期/已销户
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleBankCard(TimestampMixin, Base):
    """卡片管理-银行卡：储蓄卡/信用卡，实体/虚拟。"""

    __tablename__ = "lifestyle_bank_cards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    card_name: Mapped[str] = mapped_column(String(64))  # 卡片名称
    card_holder: Mapped[str | None] = mapped_column(String(32))  # 姓名
    bank: Mapped[str] = mapped_column(String(64), index=True)  # 银行
    card_category: Mapped[str] = mapped_column(
        String(16), default="debit"
    )  # credit/debit 信用卡/储蓄卡
    card_form: Mapped[str] = mapped_column(
        String(16), default="physical"
    )  # physical/virtual 实体卡/虚拟卡
    card_number: Mapped[str | None] = mapped_column(String(64))  # 卡号（可填部分）
    balance: Mapped[float | None] = mapped_column(Float, default=0)  # 余额
    credit_limit: Mapped[float | None] = mapped_column(Float, default=0)  # 信用额度
    billing_day: Mapped[int | None] = mapped_column(Integer)  # 账单日
    due_day: Mapped[int | None] = mapped_column(Integer)  # 还款日
    expire_date: Mapped[date | None] = mapped_column(Date)  # 有效期
    status: Mapped[str] = mapped_column(
        String(16), default="active"
    )  # active/frozen/expired/closed 正常/冻结/已过期/已注销
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleCarrier(TimestampMixin, Base):
    """卡片管理-运营商平台设置：可维护的运营商平台列表。"""

    __tablename__ = "lifestyle_carriers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), unique=True, index=True)  # 平台名称
    website: Mapped[str | None] = mapped_column(String(128))  # 官网/链接
    contact: Mapped[str | None] = mapped_column(String(64))  # 客服电话
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleCardBill(TimestampMixin, Base):
    """卡片管理-扣账账单：手机号卡按月的扣账/缴费记录。"""

    __tablename__ = "lifestyle_card_bills"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    phone_card_id: Mapped[int] = mapped_column(Integer, index=True)  # 关联手机卡
    bill_month: Mapped[date] = mapped_column(Date, index=True)  # 账单月份
    amount: Mapped[float] = mapped_column(Float)  # 扣账金额
    deducted_date: Mapped[date | None] = mapped_column(Date)  # 扣账日期
    paid: Mapped[bool] = mapped_column(Boolean, default=True)  # 是否已扣账成功
    note: Mapped[str | None] = mapped_column(Text)


class LifestyleLifeReport(TimestampMixin, Base):
    """生活报告：按月聚合各生活模块数据生成的报告，支持 PDF 导出。"""

    __tablename__ = "lifestyle_life_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128))  # 报告标题
    period_label: Mapped[str] = mapped_column(String(16))  # 周期标签，如 2026-09
    period_start: Mapped[date] = mapped_column(Date)  # 统计起始
    period_end: Mapped[date] = mapped_column(Date)  # 统计结束
    summary: Mapped[str | None] = mapped_column(Text)  # 概览摘要
    content: Mapped[str] = mapped_column(Text)  # JSON 结构内容


class LifestyleTodo(TimestampMixin, Base):
    """待办清单：待办事项。"""

    __tablename__ = "lifestyle_todos"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128), index=True)  # 事项
    category: Mapped[str | None] = mapped_column(String(32))  # 分类
    priority: Mapped[str] = mapped_column(
        String(8), default="medium"
    )  # high/medium/low
    due_date: Mapped[date | None] = mapped_column(Date)  # 截止日期
    done: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否完成
    note: Mapped[str | None] = mapped_column(Text)