from datetime import date, datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class ORMRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


class VitalsSleepCreate(BaseModel):
    record_date: date
    blood_pressure_high: int | None = Field(None, ge=0)
    blood_pressure_low: int | None = Field(None, ge=0)
    heart_rate: int | None = Field(None, ge=0)
    blood_oxygen: float | None = Field(None, ge=0, le=100)
    weight: float | None = Field(None, ge=0)
    body_temp: float | None = Field(None, ge=0)
    sleep_duration_min: int | None = Field(None, ge=0)
    deep_sleep_min: int | None = Field(None, ge=0)
    light_sleep_min: int | None = Field(None, ge=0)
    wake_count: int | None = Field(None, ge=0)
    sleep_quality: int | None = Field(None, ge=1, le=10)
    note: str | None = None


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
