from datetime import date, datetime, time
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, model_validator

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


def _compute_sleep_min(bedtime: time | None, wake_time: time | None) -> int | None:
    """根据睡觉/起床时间计算睡眠时长（分钟），跨零点时自动加一天。"""
    if bedtime is None or wake_time is None:
        return None
    start = bedtime.hour * 60 + bedtime.minute
    end = wake_time.hour * 60 + wake_time.minute
    if end < start:
        end += 24 * 60
    return end - start


class VitalsSleepCreate(BaseModel):
    record_date: date
    blood_pressure_high: int | None = Field(None, ge=0)
    blood_pressure_low: int | None = Field(None, ge=0)
    heart_rate: int | None = Field(None, ge=0)
    blood_oxygen: float | None = Field(None, ge=0, le=100)
    blood_glucose: float | None = Field(None, ge=0)
    body_temp: float | None = Field(None, ge=0)
    bedtime: time | None = None
    wake_time: time | None = None
    sleep_duration_min: int | None = Field(None, ge=0)
    deep_sleep_min: int | None = Field(None, ge=0)
    light_sleep_min: int | None = Field(None, ge=0)
    wake_count: int | None = Field(None, ge=0)
    sleep_quality: int | None = Field(None, ge=1, le=10)
    note: str | None = None

    @model_validator(mode="before")
    @classmethod
    def auto_sleep_duration(cls, data):
        from datetime import time as _time

        if not isinstance(data, dict):
            return data
        duration = data.get("sleep_duration_min")
        if duration is not None:
            return data
        bedtime = data.get("bedtime")
        wake = data.get("wake_time")
        if bedtime is not None and wake is not None:
            try:
                b = bedtime if isinstance(bedtime, _time) else _time.fromisoformat(str(bedtime))
                w = wake if isinstance(wake, _time) else _time.fromisoformat(str(wake))
                data["sleep_duration_min"] = _compute_sleep_min(b, w)
            except (ValueError, TypeError):
                pass
        return data


class VitalsSleepRead(VitalsSleepCreate, ORMRead):
    pass


class FitnessCreate(BaseModel):
    record_date: date
    exercise_type: str
    duration_min: int = Field(ge=0)
    calories: float | None = Field(None, ge=0)
    distance_km: float | None = Field(None, ge=0)
    note: str | None = None


class FitnessRead(FitnessCreate, ORMRead):
    pass


class StepsCreate(BaseModel):
    record_date: date
    steps: int = Field(ge=0)
    distance_km: float | None = Field(None, ge=0)
    calories: float | None = Field(None, ge=0)


class StepsRead(StepsCreate, ORMRead):
    pass


class CheckupCreate(BaseModel):
    check_date: date
    item_name: str
    value: float | None = None
    unit: str | None = None
    reference_range: str | None = None
    result: str | None = Field(None, pattern="^(normal|high|low)$")
    note: str | None = None


class CheckupRead(CheckupCreate, ORMRead):
    pass


class ReportCreate(BaseModel):
    report_date: date
    title: str
    summary: str | None = None
    content: str | None = None


class ReportRead(ReportCreate, ORMRead):
    pass


class MedicationCreate(BaseModel):
    record_date: date
    medicine_name: str
    dosage: str | None = None
    frequency: str | None = None
    taken: bool = False
    note: str | None = None


class MedicationRead(MedicationCreate, ORMRead):
    pass


class PageOut(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
