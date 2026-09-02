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

    @model_validator(mode="after")
    def auto_calories(self):
        if self.calories is None and self.duration_min:
            weight = 65.0
            from app.api.knowledge.fitness import estimate_calories

            est, key = estimate_calories(self.exercise_type, self.duration_min, weight)
            if key is not None:
                self.calories = est
        return self


class FitnessRead(FitnessCreate, ORMRead):
    pass


class DietCreate(BaseModel):
    record_date: date
    meal_type: str = Field(pattern="^(breakfast|lunch|dinner|snack)$")
    food_name: str
    weight_g: float = Field(gt=0)
    calories: float | None = Field(None, ge=0)
    protein: float | None = Field(None, ge=0)
    carbs: float | None = Field(None, ge=0)
    fat: float | None = Field(None, ge=0)
    note: str | None = None

    @model_validator(mode="after")
    def auto_nutrition(self):
        if self.calories is None:
            from app.api.knowledge.fitness import estimate_nutrition

            est = estimate_nutrition(self.food_name, self.weight_g)
            self.calories = est["calories"]
            if self.protein is None:
                self.protein = est["protein"]
            if self.carbs is None:
                self.carbs = est["carbs"]
            if self.fat is None:
                self.fat = est["fat"]
        return self


class DietRead(DietCreate, ORMRead):
    pass


class BodyCreate(BaseModel):
    record_date: date
    gender: str | None = Field(None, pattern="^(male|female)$")
    height_cm: float | None = Field(None, gt=0)
    weight_kg: float | None = Field(None, gt=0)
    bmi: float | None = Field(None, gt=0)
    body_fat_percent: float | None = Field(None, ge=0)
    fat_mass_kg: float | None = Field(None, ge=0)
    visceral_fat: float | None = Field(None, ge=0)
    subcutaneous_fat_percent: float | None = Field(None, ge=0)
    subcutaneous_fat_kg: float | None = Field(None, ge=0)
    muscle_percent: float | None = Field(None, ge=0)
    muscle_kg: float | None = Field(None, ge=0)
    skeletal_muscle_percent: float | None = Field(None, ge=0)
    skeletal_muscle_kg: float | None = Field(None, ge=0)
    water_percent: float | None = Field(None, ge=0)
    water_kg: float | None = Field(None, ge=0)
    protein_percent: float | None = Field(None, ge=0)
    protein_kg: float | None = Field(None, ge=0)
    bone_percent: float | None = Field(None, ge=0)
    bone_kg: float | None = Field(None, ge=0)
    foot_length_cm: float | None = Field(None, ge=0)
    hip_circumference_cm: float | None = Field(None, ge=0)
    waist_circumference_cm: float | None = Field(None, ge=0)
    chest_circumference_cm: float | None = Field(None, ge=0)
    neck_circumference_cm: float | None = Field(None, ge=0)
    note: str | None = None

    @model_validator(mode="after")
    def auto_bmi(self):
        if self.bmi is None and self.height_cm and self.weight_kg:
            h = self.height_cm / 100
            self.bmi = round(self.weight_kg / (h * h), 1)
        return self


class BodyRead(BodyCreate, ORMRead):
    pass


class StepsCreate(BaseModel):
    record_date: date
    period: str = "full"
    steps: int = Field(ge=0)
    stride_cm: float | None = Field(None, ge=0)
    distance_km: float | None = Field(None, ge=0)
    calories: float | None = Field(None, ge=0)

    @model_validator(mode="after")
    def auto_distance_calories(self):
        stride = self.stride_cm if isinstance(self.stride_cm, (int, float)) else 70.0
        if self.distance_km is None:
            self.distance_km = round(self.steps * stride / 100000, 2)
        if self.calories is None:
            self.calories = round(self.steps * 0.04, 1)
        return self


class StepsRead(StepsCreate, ORMRead):
    pass


class StepSettingCreate(BaseModel):
    stride_cm: float = Field(ge=0)


class StepSettingRead(StepSettingCreate, ORMRead):
    pass


class CheckupCreate(BaseModel):
    check_date: date
    template_id: int | None = None
    item_name: str
    value: float | None = None
    unit: str | None = None
    ref_low: float | None = None
    ref_high: float | None = None
    reference_range: str | None = None
    result: str | None = Field(None, pattern="^(normal|high|low)$")
    note: str | None = None

    @model_validator(mode="after")
    def auto_result(self):
        # 自动生成参考范围展示文本
        if not self.reference_range and (self.ref_low is not None or self.ref_high is not None):
            lo = f"{self.ref_low:g}" if self.ref_low is not None else ""
            hi = f"{self.ref_high:g}" if self.ref_high is not None else ""
            self.reference_range = f"{lo}~{hi}" if lo and hi else lo or hi
        # 依据参考范围自动判断是否正常
        if self.result is None and self.value is not None:
            if self.ref_high is not None and self.value > self.ref_high:
                self.result = "high"
            elif self.ref_low is not None and self.value < self.ref_low:
                self.result = "low"
            else:
                self.result = "normal"
        return self


class CheckupRead(CheckupCreate, ORMRead):
    pass


class CheckupTemplateCreate(BaseModel):
    item_name: str
    category: str | None = None
    unit: str | None = None
    ref_low: float | None = None
    ref_high: float | None = None


class CheckupTemplateRead(CheckupTemplateCreate, ORMRead):
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
