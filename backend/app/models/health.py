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
    """健身运动：运动记录。"""

    __tablename__ = "health_fitness"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    exercise_type: Mapped[str] = mapped_column(String(32))  # 运动类型
    duration_min: Mapped[int] = mapped_column(Integer)  # 时长(分钟)
    calories: Mapped[float | None] = mapped_column(Float)  # 消耗千卡
    distance_km: Mapped[float | None] = mapped_column(Float)  # 距离 km
    note: Mapped[str | None] = mapped_column(Text)


class HealthSteps(TimestampMixin, Base):
    """步数统计：每日步数。"""

    __tablename__ = "health_steps"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    steps: Mapped[int] = mapped_column(Integer)  # 步数
    distance_km: Mapped[float | None] = mapped_column(Float)
    calories: Mapped[float | None] = mapped_column(Float)


class HealthCheckup(TimestampMixin, Base):
    """体检指标：各项体检数据。"""

    __tablename__ = "health_checkup"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    check_date: Mapped[date] = mapped_column(Date, index=True)
    item_name: Mapped[str] = mapped_column(String(64), index=True)  # 指标名
    value: Mapped[float | None] = mapped_column(Float)  # 数值
    unit: Mapped[str | None] = mapped_column(String(32))  # 单位
    reference_range: Mapped[str | None] = mapped_column(String(128))  # 参考范围
    result: Mapped[str | None] = mapped_column(String(16))  # normal/high/low
    note: Mapped[str | None] = mapped_column(Text)


class HealthReport(TimestampMixin, Base):
    """健康报告：汇总报告。"""

    __tablename__ = "health_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    report_date: Mapped[date] = mapped_column(Date, index=True)
    title: Mapped[str] = mapped_column(String(128))
    summary: Mapped[str | None] = mapped_column(Text)
    content: Mapped[str | None] = mapped_column(Text)


class HealthMedication(TimestampMixin, Base):
    """用药跟踪：每日用药记录。"""

    __tablename__ = "health_medication"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    record_date: Mapped[date] = mapped_column(Date, index=True)
    medicine_name: Mapped[str] = mapped_column(String(64), index=True)
    dosage: Mapped[str | None] = mapped_column(String(64))  # 剂量
    frequency: Mapped[str | None] = mapped_column(String(64))  # 频次
    taken: Mapped[bool] = mapped_column(Boolean, default=False)  # 是否已服用
    note: Mapped[str | None] = mapped_column(Text)
