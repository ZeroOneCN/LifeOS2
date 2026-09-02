from datetime import date, datetime, time

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


class HealthVitalsSleep(TimestampMixin, Base):
    """睡眠体征：每日生命体征与睡眠质量记录。"""

    __tablename__ = "health_vitals_sleep"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    blood_pressure_high: Mapped[int | None] = mapped_column(Integer)  # 高压
    blood_pressure_low: Mapped[int | None] = mapped_column(Integer)  # 低压
    heart_rate: Mapped[int | None] = mapped_column(Integer)  # 心率
    blood_oxygen: Mapped[float | None] = mapped_column(Float)  # 血氧饱和度 %
    blood_glucose: Mapped[float | None] = mapped_column(Float)  # 血糖 mmol/L
    body_temp: Mapped[float | None] = mapped_column(Float)  # 体温 ℃
    bedtime: Mapped[time | None] = mapped_column(Time)  # 睡觉时间
    wake_time: Mapped[time | None] = mapped_column(Time)  # 起床时间
    sleep_duration_min: Mapped[int | None] = mapped_column(Integer)  # 总睡眠(分钟) 由 bedtime/wake_time 自动计算
    deep_sleep_min: Mapped[int | None] = mapped_column(Integer)  # 深睡(分钟)
    light_sleep_min: Mapped[int | None] = mapped_column(Integer)  # 浅睡(分钟)
    wake_count: Mapped[int | None] = mapped_column(Integer)  # 醒来次数
    sleep_quality: Mapped[int | None] = mapped_column(Integer)  # 睡眠质量 1-10
    note: Mapped[str | None] = mapped_column(Text)


class HealthFitness(TimestampMixin, Base):
    """健身运动：运动(热量消耗)记录。"""

    __tablename__ = "health_fitness"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    exercise_type: Mapped[str] = mapped_column(String(32))  # 运动类型
    duration_min: Mapped[int] = mapped_column(Integer)  # 时长(分钟)
    calories: Mapped[float | None] = mapped_column(Float)  # 消耗千卡(按MET自动推算)
    distance_km: Mapped[float | None] = mapped_column(Float)  # 距离 km
    note: Mapped[str | None] = mapped_column(Text)


class HealthDiet(TimestampMixin, Base):
    """饮食记录：三餐与加餐营养摄入。"""

    __tablename__ = "health_diet"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    meal_type: Mapped[str] = mapped_column(String(16))  # breakfast/lunch/dinner/snack
    food_name: Mapped[str] = mapped_column(String(64))  # 食物名称
    weight_g: Mapped[float] = mapped_column(Float)  # 重量(克)
    calories: Mapped[float] = mapped_column(Float)  # 热量(千卡)
    protein: Mapped[float | None] = mapped_column(Float)  # 蛋白质(g)
    carbs: Mapped[float | None] = mapped_column(Float)  # 碳水(g)
    fat: Mapped[float | None] = mapped_column(Float)  # 脂肪(g)
    note: Mapped[str | None] = mapped_column(Text)


class HealthBody(TimestampMixin, Base):
    """体重记录：身体成分与身材参数。"""

    __tablename__ = "health_body"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    gender: Mapped[str | None] = mapped_column(String(8))  # male/female
    height_cm: Mapped[float | None] = mapped_column(Float)  # 身高 cm
    weight_kg: Mapped[float | None] = mapped_column(Float)  # 体重 kg
    bmi: Mapped[float | None] = mapped_column(Float)  # BMI(自动计算)
    body_fat_percent: Mapped[float | None] = mapped_column(Float)  # 体脂率 %
    fat_mass_kg: Mapped[float | None] = mapped_column(Float)  # 脂肪量 kg
    visceral_fat: Mapped[float | None] = mapped_column(Float)  # 内脏脂肪等级
    subcutaneous_fat_percent: Mapped[float | None] = mapped_column(Float)  # 皮下脂肪率 %
    subcutaneous_fat_kg: Mapped[float | None] = mapped_column(Float)  # 皮下脂肪量 kg
    muscle_percent: Mapped[float | None] = mapped_column(Float)  # 肌肉率 %
    muscle_kg: Mapped[float | None] = mapped_column(Float)  # 肌肉量 kg
    skeletal_muscle_percent: Mapped[float | None] = mapped_column(Float)  # 骨骼肌率 %
    skeletal_muscle_kg: Mapped[float | None] = mapped_column(Float)  # 骨骼肌量 kg
    water_percent: Mapped[float | None] = mapped_column(Float)  # 水分率 %
    water_kg: Mapped[float | None] = mapped_column(Float)  # 水分量 kg
    protein_percent: Mapped[float | None] = mapped_column(Float)  # 蛋白质占比 %
    protein_kg: Mapped[float | None] = mapped_column(Float)  # 蛋白质含量 kg
    bone_percent: Mapped[float | None] = mapped_column(Float)  # 骨量占比 %
    bone_kg: Mapped[float | None] = mapped_column(Float)  # 骨量 kg
    foot_length_cm: Mapped[float | None] = mapped_column(Float)  # 足长 cm
    hip_circumference_cm: Mapped[float | None] = mapped_column(Float)  # 臀围 cm
    waist_circumference_cm: Mapped[float | None] = mapped_column(Float)  # 腰围 cm
    chest_circumference_cm: Mapped[float | None] = mapped_column(Float)  # 胸围 cm
    neck_circumference_cm: Mapped[float | None] = mapped_column(Float)  # 颈围 cm
    note: Mapped[str | None] = mapped_column(Text)


class HealthSteps(TimestampMixin, Base):
    """步数统计：按时间段录入每日步数。"""

    __tablename__ = "health_steps"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    period: Mapped[str] = mapped_column(String(8), default="full", index=True)  # 时间段(full 代表全天/0点)
    steps: Mapped[int] = mapped_column(Integer)  # 步数
    stride_cm: Mapped[float | None] = mapped_column(Float)  # 录入时的每步步幅 cm
    distance_km: Mapped[float | None] = mapped_column(Float)  # 由步幅自动计算
    calories: Mapped[float | None] = mapped_column(Float)


class HealthStepSetting(TimestampMixin, Base):
    """步数设置：每步步幅（固定单行 id=1）。"""

    __tablename__ = "health_step_setting"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    stride_cm: Mapped[float] = mapped_column(Float, default=70.0)  # 每步步幅 cm


class HealthCheckupTemplate(TimestampMixin, Base):
    """体检指标标准模板。"""

    __tablename__ = "health_checkup_template"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_name: Mapped[str] = mapped_column(String(64), index=True)  # 指标名
    category: Mapped[str | None] = mapped_column(String(32))  # 类别
    unit: Mapped[str | None] = mapped_column(String(32))  # 单位
    ref_low: Mapped[float | None] = mapped_column(Float)  # 参考下限
    ref_high: Mapped[float | None] = mapped_column(Float)  # 参考上限


class HealthCheckup(TimestampMixin, Base):
    """体检指标：各项体检数据。"""

    __tablename__ = "health_checkup"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    check_date: Mapped[date] = mapped_column(Date, index=True)
    template_id: Mapped[int | None] = mapped_column(Integer)  # 关联模板
    item_name: Mapped[str] = mapped_column(String(64), index=True)  # 指标名
    value: Mapped[float | None] = mapped_column(Float)  # 数值
    unit: Mapped[str | None] = mapped_column(String(32))  # 单位
    ref_low: Mapped[float | None] = mapped_column(Float)  # 参考下限
    ref_high: Mapped[float | None] = mapped_column(Float)  # 参考上限
    reference_range: Mapped[str | None] = mapped_column(String(128))  # 参考范围(展示文本)
    result: Mapped[str | None] = mapped_column(String(16))  # normal/high/low
    note: Mapped[str | None] = mapped_column(Text)


class HealthCheckupPanel(TimestampMixin, Base):
    """体检组合模板（套餐/检查组）：一个组合包含多个体检指标。"""

    __tablename__ = "health_checkup_panel"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    panel_name: Mapped[str] = mapped_column(String(64), index=True)  # 组合名
    note: Mapped[str | None] = mapped_column(String(255))  # 说明


class HealthCheckupPanelItem(TimestampMixin, Base):
    """体检组合模板明细：组合内每一项指标定义。"""

    __tablename__ = "health_checkup_panel_item"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    panel_id: Mapped[int] = mapped_column(Integer, index=True)  # 所属组合
    item_name: Mapped[str] = mapped_column(String(64))  # 指标名
    unit: Mapped[str | None] = mapped_column(String(32))  # 单位
    ref_low: Mapped[float | None] = mapped_column(Float)  # 参考下限
    ref_high: Mapped[float | None] = mapped_column(Float)  # 参考上限
    reference_range: Mapped[str | None] = mapped_column(String(128))  # 参考范围(展示文本)


class HealthReport(TimestampMixin, Base):
    """健康报告：汇总报告。"""

    __tablename__ = "health_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    report_date: Mapped[date] = mapped_column(Date, index=True)
    title: Mapped[str] = mapped_column(String(128))
    summary: Mapped[str | None] = mapped_column(Text)
    content: Mapped[str | None] = mapped_column(Text)


class HealthMedication(TimestampMixin, Base):
    """用药跟踪：每日分早/午/晚用药记录。"""

    __tablename__ = "health_medication"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    medicine_name: Mapped[str] = mapped_column(String(64), index=True)
    meal_slot: Mapped[str] = mapped_column(String(16), default="breakfast")  # breakfast/lunch/dinner
    dosage: Mapped[str | None] = mapped_column(String(64))  # 剂量
    frequency: Mapped[str | None] = mapped_column(String(64))  # 频次
    taken: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否已服用
    note: Mapped[str | None] = mapped_column(Text)


class HealthMedPurchase(TimestampMixin, Base):
    """用药跟踪：购药记录。"""

    __tablename__ = "health_med_purchase"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    buy_date: Mapped[date] = mapped_column(Date, index=True)
    medicine_name: Mapped[str] = mapped_column(String(64), index=True)
    channel: Mapped[str | None] = mapped_column(String(64))  # 购买渠道
    unit: Mapped[str | None] = mapped_column(String(32))  # 单位(盒/片)
    quantity: Mapped[float] = mapped_column(Float)  # 数量
    unit_price: Mapped[float] = mapped_column(Float)  # 单价
    total_price: Mapped[float | None] = mapped_column(Float)  # 总价
    note: Mapped[str | None] = mapped_column(Text)


class HealthMedStock(TimestampMixin, Base):
    """用药跟踪：药品库存与低库存阈值。"""

    __tablename__ = "health_med_stock"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    medicine_name: Mapped[str] = mapped_column(String(64), index=True, unique=True)
    stock_qty: Mapped[float] = mapped_column(Float)  # 当前库存
    threshold: Mapped[float | None] = mapped_column(Float)  # 低库存阈值
    unit: Mapped[str | None] = mapped_column(String(32))  # 单位
