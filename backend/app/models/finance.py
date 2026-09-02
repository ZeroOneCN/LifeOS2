from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    Integer,
    String,
    Text,
    Time,
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


class FinanceShoppingPlatform(TimestampMixin, Base):
    """购物平台：可添加管理的电商平台（淘宝/京东等）。"""

    __tablename__ = "finance_shopping_platforms"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), unique=True)  # 平台名称


class FinanceShoppingLedger(TimestampMixin, Base):
    """购物账本：用于分类管理不同场景的购物记录。"""

    __tablename__ = "finance_shopping_ledgers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), unique=True)  # 账本名称


class FinanceShoppingRecord(TimestampMixin, Base):
    """购物记录：具体的购物明细，支持多账本与 xlsx 批量导入。"""

    __tablename__ = "finance_shopping_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)  # 日期
    platform_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 平台 id
    product_name: Mapped[str] = mapped_column(String(128))  # 商品名称
    spec: Mapped[str | None] = mapped_column(String(128))  # 规格
    total_price: Mapped[float] = mapped_column(Float)  # 总价
    unit_price: Mapped[float | None] = mapped_column(Float)  # 单价
    order_no: Mapped[str | None] = mapped_column(String(64), index=True)  # 订单号
    ledger_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 账本 id
    note: Mapped[str | None] = mapped_column(Text)


class FinanceTravelLedger(TimestampMixin, Base):
    """行程账本：一次旅行的总览（多账本，随时切换）。"""

    __tablename__ = "finance_travel_ledgers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(128))  # 行程名称
    start_date: Mapped[date | None] = mapped_column(Date)  # 开始日期
    end_date: Mapped[date | None] = mapped_column(Date)  # 结束日期
    note: Mapped[str | None] = mapped_column(Text)


class FinanceTravelDetail(TimestampMixin, Base):
    """行程明细：一条旅行费用/日程，自动计算时长与实付。"""

    __tablename__ = "finance_travel_details"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ledger_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 行程账本 id
    detail_date: Mapped[date] = mapped_column(Date, index=True)  # 日期
    begin_time: Mapped[Time | None] = mapped_column(Time)  # 开始时间
    end_time: Mapped[Time | None] = mapped_column(Time)  # 结束时间
    category: Mapped[str] = mapped_column(String(32), index=True)  # 分类：交通/住宿/餐饮/门票等
    item: Mapped[str] = mapped_column(String(128))  # 项目
    original_price: Mapped[float] = mapped_column(Float)  # 原价
    discount: Mapped[float] = mapped_column(Float, default=0)  # 优惠
    actual_price: Mapped[float] = mapped_column(Float)  # 实付 = 原价 - 优惠
    transport_info: Mapped[str | None] = mapped_column(String(128))  # 交通信息（航班/车次等）
    payment_method: Mapped[str | None] = mapped_column(String(32))  # 支付方式
    note: Mapped[str | None] = mapped_column(Text)


class FinanceHousing(TimestampMixin, Base):
    """住房信息：租房渠道/押金/杂费/租期等，用于组合月租分析。"""

    __tablename__ = "finance_housing"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(128))  # 房屋名称
    short_name: Mapped[str | None] = mapped_column(String(64))  # 显示缩写（小区名等）
    channel: Mapped[str | None] = mapped_column(String(64))  # 租房渠道
    orientation: Mapped[str | None] = mapped_column(String(16))  # 房屋朝向
    move_in_date: Mapped[date] = mapped_column(Date)  # 入住时间
    move_out_date: Mapped[date | None] = mapped_column(Date)  # 退租时间
    rent_term: Mapped[str] = mapped_column(String(16), default="monthly")  # monthly/quarterly 按月/按季付
    actual_monthly_rent: Mapped[float] = mapped_column(Float)  # 实际月租
    deposit: Mapped[float | None] = mapped_column(Float, default=0)  # 押金
    agent_fee: Mapped[float | None] = mapped_column(Float, default=0)  # 中介费
    clean_fee: Mapped[float | None] = mapped_column(Float, default=0)  # 保洁费
    service_fee: Mapped[float | None] = mapped_column(Float, default=0)  # 服务费
    laundry_fee: Mapped[float | None] = mapped_column(Float, default=0)  # 洗衣费
    note: Mapped[str | None] = mapped_column(Text)


class FinanceUtility(TimestampMixin, Base):
    """水电燃气/宽带费用账单。"""

    __tablename__ = "finance_utilities"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    housing_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 关联住房
    bill_month: Mapped[date] = mapped_column(Date, index=True)  # 账单月份
    fee_type: Mapped[str] = mapped_column(String(16), index=True)  # 水/电/气/网
    amount: Mapped[float] = mapped_column(Float)  # 金额
    due_date: Mapped[date | None] = mapped_column(Date)  # 到期日
    paid: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否已支付
    note: Mapped[str | None] = mapped_column(Text)


class FinanceSubscription(TimestampMixin, Base):
    """服务订阅：会员/服务器等周期性付费订阅。"""

    __tablename__ = "finance_subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(128))  # 订阅名称
    category: Mapped[str] = mapped_column(String(32), index=True)  # 分类（会员/服务器/软件等）
    billing_cycle: Mapped[str] = mapped_column(String(16), default="month")  # month/quarter/year
    amount: Mapped[float] = mapped_column(Float)  # 每期金额
    start_date: Mapped[date] = mapped_column(Date)  # 起始时间
    remind_days: Mapped[int] = mapped_column(Integer, default=30)  # 过期前多少天提醒
    status: Mapped[str] = mapped_column(String(16), default="active")  # active/expired/cancelled
    note: Mapped[str | None] = mapped_column(Text)


class FinanceLoanPlatform(TimestampMixin, Base):
    """借款平台：账单日/还款日/额度/累计欠款。"""

    __tablename__ = "finance_loan_platforms"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64))  # 平台名称
    bill_day: Mapped[int | None] = mapped_column(Integer)  # 账单日
    due_day: Mapped[int | None] = mapped_column(Integer)  # 还款日
    credit_limit: Mapped[float | None] = mapped_column(Float)  # 额度
    note: Mapped[str | None] = mapped_column(Text)


class FinanceLoanBill(TimestampMixin, Base):
    """网贷账单：按月分期的还款账单。"""

    __tablename__ = "finance_loan_bills"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    platform_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 借款平台
    bill_month: Mapped[date] = mapped_column(Date, index=True)  # 账单月份
    due_date: Mapped[date | None] = mapped_column(Date)  # 到期日
    amount: Mapped[float] = mapped_column(Float)  # 欠款（含利息，不单独算）
    paid_amount: Mapped[float] = mapped_column(Float, default=0)  # 已还
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending/partial/cleared
    note: Mapped[str | None] = mapped_column(Text)


class FinanceRepayment(TimestampMixin, Base):
    """还款记录：网贷账单的还款明细。"""

    __tablename__ = "finance_repayments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    bill_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 关联账单
    repay_date: Mapped[date] = mapped_column(Date)  # 还款日期
    amount: Mapped[float] = mapped_column(Float)  # 还款金额
    method: Mapped[str | None] = mapped_column(String(32))  # 还款方式
    note: Mapped[str | None] = mapped_column(Text)


class FinanceReminder(TimestampMixin, Base):
    """账单提醒：待办缴费/还款提醒。"""

    __tablename__ = "finance_reminders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    reminder_date: Mapped[date] = mapped_column(Date, index=True)
    title: Mapped[str] = mapped_column(String(128))  # 提醒标题
    category: Mapped[str] = mapped_column(String(32), index=True)  # 类型
    amount: Mapped[float | None] = mapped_column(Float)  # 金额
    due_date: Mapped[date | None] = mapped_column(Date)  # 截止日期
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending/done
    note: Mapped[str | None] = mapped_column(Text)


class FinancePlan(TimestampMixin, Base):
    """财务规划：储蓄/预算/投资等目标。"""

    __tablename__ = "finance_planning"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    plan_date: Mapped[date] = mapped_column(Date, index=True)
    plan_type: Mapped[str] = mapped_column(String(32), index=True)  # 储蓄/预算/投资/目标
    title: Mapped[str] = mapped_column(String(128))  # 目标名称
    target_amount: Mapped[float | None] = mapped_column(Float)  # 目标金额
    saved_amount: Mapped[float | None] = mapped_column(Float)  # 已存金额
    status: Mapped[str] = mapped_column(String(16), default="active")  # active/done/abandoned
    note: Mapped[str | None] = mapped_column(Text)


class FinanceDebt(TimestampMixin, Base):
    """债务管理：借出/借入款项追踪。"""

    __tablename__ = "finance_debts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    debt_date: Mapped[date] = mapped_column(Date, index=True)  # 借款/出借日期
    name: Mapped[str] = mapped_column(String(128))  # 债务名称
    direction: Mapped[str] = mapped_column(String(8), index=True)  # lend=借出 / borrow=借入
    counterparty: Mapped[str | None] = mapped_column(String(64))  # 对方（借款人/债权人）
    amount: Mapped[float] = mapped_column(Float)  # 总金额（本金）
    remaining: Mapped[float | None] = mapped_column(Float)  # 剩余未还/未收金额
    interest_rate: Mapped[float | None] = mapped_column(Float)  # 年利率（%）
    due_date: Mapped[date | None] = mapped_column(Date)  # 到期日
    status: Mapped[str] = mapped_column(String(16), default="active")  # active=进行中 / settled=已结清
    note: Mapped[str | None] = mapped_column(Text)


class FinanceInvestment(TimestampMixin, Base):
    """投资记账：各投资平台的盈亏总额，无需过细。"""

    __tablename__ = "finance_investments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    platform: Mapped[str] = mapped_column(String(64))  # 平台名称
    account: Mapped[str | None] = mapped_column(String(64))  # 平台账号
    category: Mapped[str] = mapped_column(String(24), index=True)  # 美股/港股/外汇/加密货币-合约等
    pnl: Mapped[float] = mapped_column(Float)  # 盈亏总额
    note: Mapped[str | None] = mapped_column(Text)


class FinanceMemo(TimestampMixin, Base):
    """备忘录：模糊记忆或有待处理事项。"""

    __tablename__ = "finance_memos"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128))  # 标题
    content: Mapped[str | None] = mapped_column(Text)  # 内容
    memo_date: Mapped[date | None] = mapped_column(Date)  # 日期


class FinanceCurrency(TimestampMixin, Base):
    """汇率设置：按币种相对人民币的汇率，用于金额切换显示。"""

    __tablename__ = "finance_currencies"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    currency: Mapped[str] = mapped_column(String(8), unique=True, index=True)  # USD/HKD/CNY
    name: Mapped[str | None] = mapped_column(String(32))  # 币种名称
    rate_to_cny: Mapped[float] = mapped_column(Float)  # 1 单位该币种 = 多少人民币
    symbol: Mapped[str | None] = mapped_column(String(8))  # 符号，如 $ / HK$ / ¥


class FinanceReport(TimestampMixin, Base):
    """财务报告：按月聚合各财务模块数据生成的报告，支持 PDF 导出。"""

    __tablename__ = "finance_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128))  # 报告标题
    period_label: Mapped[str] = mapped_column(String(16))  # 周期标签，如 2026-09
    period_start: Mapped[date] = mapped_column(Date)  # 统计起始
    period_end: Mapped[date] = mapped_column(Date)  # 统计结束
    summary: Mapped[str | None] = mapped_column(Text)  # 概览摘要
    content: Mapped[str] = mapped_column(Text)  # JSON 结构内容


class FinanceTravelReport(TimestampMixin, Base):
    """旅行报告：按行程明细汇总生成并保存的报告，支持预览与 PDF 导出。"""

    __tablename__ = "finance_travel_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(128))  # 报告标题
    ledger_id: Mapped[int | None] = mapped_column(Integer, index=True)  # 关联行程账本
    period_start: Mapped[date] = mapped_column(Date)  # 统计起始
    period_end: Mapped[date] = mapped_column(Date)  # 统计结束
    summary: Mapped[str | None] = mapped_column(Text)  # 概览摘要
    content: Mapped[str] = mapped_column(Text)  # JSON 结构内容
