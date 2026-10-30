import json
from datetime import date, datetime
from statistics import fmean

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import ActivityLog, HealthVitalsSleep
from app.schemas.health import VitalsSleepCreate, VitalsSleepRead

router = APIRouter()


def _vitals_stats(db: Session, days: int, user_id: int) -> dict:
    # 体征统计支持按近 N 天过滤（days=0 返回全部）
    since = days_since(days)
    stmt = select(HealthVitalsSleep).where(HealthVitalsSleep.user_id == user_id)
    if since is not None:
        stmt = stmt.where(HealthVitalsSleep.record_date >= since)
    rows = db.scalars(
        stmt.order_by(HealthVitalsSleep.record_date)
    ).all()

    def avg(attr: str) -> float | None:
        values = [getattr(r, attr) for r in rows if getattr(r, attr) is not None]
        return round(fmean(values), 1) if values else None

    # 最近一次手环自动采集的日期（用于前端展示采集概览）
    hr_rows = [r for r in rows if r.hr_samples]
    latest_hr = None
    if hr_rows:
        r = hr_rows[-1]
        latest_hr = {
            "record_date": r.record_date,
            "hr_avg": r.hr_avg,
            "hr_min": r.hr_min,
            "hr_max": r.hr_max,
            "hr_samples": r.hr_samples,
            "hr_source": r.hr_source,
            "hr_measured_at": r.hr_measured_at,
        }

    return {
        "trend": [
            {
                "record_date": r.record_date,
                "blood_pressure_high": r.blood_pressure_high,
                "blood_pressure_low": r.blood_pressure_low,
                "heart_rate": r.heart_rate,
                "blood_oxygen": r.blood_oxygen,
                "blood_glucose": r.blood_glucose,
                "body_temp": r.body_temp,
                "sleep_duration_min": r.sleep_duration_min,
                "deep_sleep_min": r.deep_sleep_min,
                "light_sleep_min": r.light_sleep_min,
                "wake_count": r.wake_count,
                "sleep_quality": r.sleep_quality,
                "hr_min": r.hr_min,
                "hr_max": r.hr_max,
                "hr_avg": r.hr_avg,
                "hr_samples": r.hr_samples,
            }
            for r in rows
        ],
        "avg": {
            "blood_pressure_high": avg("blood_pressure_high"),
            "blood_pressure_low": avg("blood_pressure_low"),
            "heart_rate": avg("heart_rate"),
            "blood_oxygen": avg("blood_oxygen"),
            "blood_glucose": avg("blood_glucose"),
            "body_temp": avg("body_temp"),
            "sleep_duration_min": avg("sleep_duration_min"),
            "deep_sleep_min": avg("deep_sleep_min"),
            "sleep_quality": avg("sleep_quality"),
        },
        "latest_hr": latest_hr,
        "record_count": len(rows),
    }


router = crud_router(
    prefix="/health/vitals-sleep",
    tag="health-vitals-sleep",
    model=HealthVitalsSleep,
    create_schema=VitalsSleepCreate,
    read_schema=VitalsSleepRead,
    order_by=HealthVitalsSleep.record_date,
    date_column="record_date",
    stats_func=_vitals_stats,
)


class VitalsHrBleSync(BaseModel):
    """前端蓝牙采集的手环心率批量数据。

    前端通过 Web Bluetooth 监听小米手环广播包，
    把采集到的心率样本批量 POST 上来。
    """

    samples: list[int] = Field(..., min_length=1, description="心率样本列表（bpm）")
    source: str = Field("xiaomi", max_length=16, description="数据来源 xiaomi/standard")
    measured_at: datetime | None = None


@router.post("/blesync")
def vitals_hr_blesync(
    payload: VitalsHrBleSync,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """接收前端蓝牙手环心率数据，按今天聚合写入 health_vitals_sleep。"""
    samples = [s for s in payload.samples if 20 <= s <= 250]
    if not samples:
        return {"accepted": False, "reason": "no_valid_samples"}

    today = date.today()
    row = db.scalar(
        select(HealthVitalsSleep)
        .where(
            HealthVitalsSleep.user_id == current_user.id,
            HealthVitalsSleep.record_date == today,
        )
        .order_by(HealthVitalsSleep.id)
        .limit(1)
    )
    if row is None:
        row = HealthVitalsSleep(user_id=current_user.id, record_date=today)
        db.add(row)

    # 合并：前端传来的样本 + 数据库已有样本
    all_samples = list(samples)
    if row.hr_samples and row.hr_avg is not None:
        # 用已有均值反推历史总值，再加新样本
        existing_total = row.hr_samples * row.hr_avg
        new_total = existing_total + sum(samples)
        row.hr_samples = row.hr_samples + len(samples)
        row.hr_avg = round(new_total / row.hr_samples, 1)
        row.hr_min = min(row.hr_min or 999, min(samples))
        row.hr_max = max(row.hr_max or 0, max(samples))
    else:
        row.hr_samples = len(samples)
        row.hr_avg = round(sum(samples) / len(samples), 1)
        row.hr_min = min(samples)
        row.hr_max = max(samples)

    # heart_rate 主字段也记录当日均值，兼容趋势图展示
    row.heart_rate = int(round(row.hr_avg))
    row.hr_source = payload.source
    row.hr_measured_at = payload.measured_at or datetime.now()

    db.flush()

    # 活动日志：每天只保留 1 条，后续用最新覆盖
    summary = f"前端蓝牙同步心率 {row.hr_avg} bpm（{row.hr_samples} 个样本，{row.hr_min}~{row.hr_max}）"
    detail = json.dumps(
        {
            "record_date": today.isoformat(),
            "hr_avg": row.hr_avg,
            "hr_min": row.hr_min,
            "hr_max": row.hr_max,
            "samples": row.hr_samples,
            "source": row.hr_source,
            "measured_at": row.hr_measured_at.strftime("%Y-%m-%d %H:%M:%S") if row.hr_measured_at else None,
            "device": "web-bluetooth",
        },
        ensure_ascii=False,
    )[:2000]
    log = db.scalar(
        select(ActivityLog)
        .where(
            ActivityLog.user_id == current_user.id,
            ActivityLog.module == "health/vitals-sleep",
            ActivityLog.resource_id == row.id,
        )
        .order_by(ActivityLog.id)
        .limit(1)
    )
    if log is None:
        db.add(
            ActivityLog(
                user_id=current_user.id,
                action="create",
                module="health/vitals-sleep",
                resource_type="vitals",
                resource_id=row.id,
                summary=summary,
                detail=detail,
                user_agent="web-bluetooth",
            )
        )
    else:
        log.action = "update"
        log.summary = summary
        log.detail = detail

    db.commit()
    return {
        "accepted": True,
        "record_date": today.isoformat(),
        "hr_avg": row.hr_avg,
        "hr_min": row.hr_min,
        "hr_max": row.hr_max,
        "hr_samples": row.hr_samples,
    }
