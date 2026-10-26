from statistics import fmean

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.core.config import settings
from app.core.database import get_db
from app.models import HealthVitalsSleep, UserProfile
from app.schemas.health import HRIngest, VitalsSleepCreate, VitalsSleepRead

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


def _register_fixed(router: APIRouter) -> None:
    """注册固定路径端点（必须先于 crud_router 的动态 /{item_id} 注册）。"""

    @router.post("/ingest")
    def ingest_heart_rate(
        payload: HRIngest,
        x_watch_key: str | None = Header(default=None, alias="X-Watch-Key"),
        db: Session = Depends(get_db),
    ) -> dict:
        """接收手环桥接服务上报的每日心率聚合，按 (user_id, record_date) 幂等写入。

        仅更新心率采集相关列（heart_rate 写入当日均值，另存 hr_* 统计），
        不会改动用户手工填写的血压、血氧、体温、睡眠等字段。
        """
        if not settings.WATCH_INGEST_KEY or x_watch_key != settings.WATCH_INGEST_KEY:
            raise HTTPException(status_code=401, detail="无效的采集密钥")
        user_id = settings.WATCH_USER_ID
        if not user_id:
            user_id = db.scalar(
                select(UserProfile.id).order_by(UserProfile.id).limit(1)
            )
            if user_id is None:
                raise HTTPException(status_code=400, detail="系统中没有可归属的用户")
        row = db.scalar(
            select(HealthVitalsSleep)
            .where(
                HealthVitalsSleep.user_id == user_id,
                HealthVitalsSleep.record_date == payload.record_date,
            )
            .order_by(HealthVitalsSleep.id)
            .limit(1)
        )
        if row is None:
            row = HealthVitalsSleep(
                user_id=user_id, record_date=payload.record_date
            )
            db.add(row)
        # heart_rate 记录当日均值，保持与前端“心率趋势”口径一致
        row.heart_rate = int(round(payload.hr_avg))
        row.hr_avg = round(payload.hr_avg, 1)
        row.hr_min = payload.hr_min
        row.hr_max = payload.hr_max
        row.hr_samples = payload.hr_samples
        row.hr_source = payload.hr_source
        row.hr_measured_at = payload.hr_measured_at
        db.commit()
        db.refresh(row)
        return {
            "id": row.id,
            "record_date": row.record_date,
            "heart_rate": row.heart_rate,
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
    extra_routes=_register_fixed,
)
