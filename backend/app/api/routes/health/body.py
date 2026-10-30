import json
from collections import defaultdict
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import ActivityLog, HealthBody
from app.schemas.health import BodyCreate, BodyRead
from app.services.scale_collector import scale_collector

router = APIRouter()

METRIC_KEYS = [
    "weight_kg",
    "bmi",
    "body_fat_percent",
    "fat_mass_kg",
    "visceral_fat",
    "subcutaneous_fat_percent",
    "muscle_percent",
    "muscle_kg",
    "skeletal_muscle_kg",
    "water_percent",
    "protein_percent",
    "bone_kg",
]


def _latest(rows):
    if not rows:
        return None
    r = sorted(rows, key=lambda x: x.record_date, reverse=True)[0]
    bmi = r.bmi
    # 兼容历史数据：只有身高体重而无 BMI 时按公式补算
    if bmi is None and r.height_cm and r.weight_kg:
        h = r.height_cm / 100
        bmi = round(r.weight_kg / (h * h), 1)
    return {
        "id": r.id,
        "record_date": r.record_date,
        "gender": r.gender,
        "height_cm": r.height_cm,
        "weight_kg": r.weight_kg,
        "bmi": bmi,
        "body_fat_percent": r.body_fat_percent,
        "muscle_percent": r.muscle_percent,
    }


def _body_stats(db: Session, days: int, user_id: int) -> dict:
    since = days_since(days)
    stmt = select(HealthBody).where(HealthBody.user_id == user_id)
    if since is not None:
        stmt = stmt.where(HealthBody.record_date >= since)
    rows = db.scalars(
        stmt.order_by(HealthBody.record_date)
    ).all()

    trend = [{**{m: getattr(r, m) for m in METRIC_KEYS}, "record_date": r.record_date} for r in rows]
    by_date = defaultdict(list)
    for r in rows:
        by_date[r.record_date].append(r)

    changes = {}
    dates = sorted(by_date)
    if len(dates) >= 2:
        recent = by_date[dates[-1]][-1]
        prev = by_date[dates[-2]][-1]
        for m in METRIC_KEYS:
            a = getattr(recent, m)
            b = getattr(prev, m)
            if isinstance(a, (int, float)) and isinstance(b, (int, float)):
                changes[m] = round(a - b, 1)

    total_records = len(rows)
    bmi_vals = [r.bmi for r in rows if isinstance(r.bmi, (int, float))]
    weight_vals = [r.weight_kg for r in rows if isinstance(r.weight_kg, (int, float))]

    avg_bmi = round(sum(bmi_vals) / len(bmi_vals), 1) if bmi_vals else None
    avg_weight = round(sum(weight_vals) / len(weight_vals), 1) if weight_vals else None
    max_weight = max(weight_vals) if weight_vals else None
    min_weight = min(weight_vals) if weight_vals else None

    return {
        "latest": _latest(rows),
        "trend": trend,
        "changes": changes,
        "avg_bmi": avg_bmi,
        "avg_weight": avg_weight,
        "max_weight": max_weight,
        "min_weight": min_weight,
        "record_count": total_records,
    }


class BodyBleSync(BaseModel):
    """前端蓝牙采集的体重测量数据。

    由浏览器 Web Bluetooth API 解析体重秤通知后 POST 上来；
    同一天多次测量以最后一次为准覆盖。
    """

    weight_kg: float = Field(..., gt=0, lt=250, description="体重（kg）")
    height_cm: float | None = Field(None, gt=0, lt=300, description="身高（cm），提供时自动计算 BMI")
    gender: str | None = Field(None, pattern="^(male|female)$")
    impedance_ohm: float | None = Field(None, gt=0, description="阻抗（欧姆），用于体成分估算")
    body_composition: dict | None = Field(None, description="前端已估算好的体成分结果，直接落库")
    measured_at: datetime | None = Field(None, description="前端测量时间，缺省用服务器当前时间")


def _apply_body(row: HealthBody, body: dict) -> None:
    """把体成分结果写入 HealthBody 对应列。"""
    mapping = {
        "bmi": "bmi",
        "body_fat": "body_fat_percent",
        "fat_mass": "fat_mass_kg",
        "visceral_fat": "visceral_fat",
        "sub_fat_pct": "subcutaneous_fat_percent",
        "sub_fat_mass": "subcutaneous_fat_kg",
        "water": "water_percent",
        "water_mass": "water_kg",
        "protein_rate": "protein_percent",
        "protein_mass": "protein_kg",
        "bone_rate": "bone_percent",
        "bone": "bone_kg",
        "muscle_rate": "muscle_percent",
        "muscle": "muscle_kg",
        "skeletal_muscle_rate": "skeletal_muscle_percent",
        "skeletal_muscle": "skeletal_muscle_kg",
    }
    for src, col in mapping.items():
        v = body.get(src)
        if isinstance(v, (int, float)):
            setattr(row, col, v)


def _register_extra_routes(api: APIRouter) -> None:
    """注册体重秤采集状态与前端蓝牙同步接口（需在 /{item_id} 之前注册）。"""

    @api.get("/scale-status")
    def scale_status(_user=Depends(get_current_user)) -> dict:
        """查询体重秤采集器状态：开关、扫描/连接情况、最近一次测量与写入。"""
        return scale_collector.status()

    @api.post("/blesync", response_model=BodyRead)
    def body_blesync(
        payload: BodyBleSync,
        db: Session = Depends(get_db),
        current_user=Depends(get_current_user),
    ):
        """接收前端蓝牙体重秤数据，写入当天 health_body（存在则覆盖）。"""
        today = date.today()
        row = db.scalar(
            select(HealthBody)
            .where(HealthBody.user_id == current_user.id, HealthBody.record_date == today)
            .order_by(HealthBody.id)
            .limit(1)
        )
        created = row is None
        if created:
            row = HealthBody(user_id=current_user.id, record_date=today)
            db.add(row)

        kg = round(payload.weight_kg, 2)
        row.weight_kg = kg
        if payload.gender:
            row.gender = payload.gender
        if payload.height_cm:
            row.height_cm = payload.height_cm
            # 有身高体重就自动算 BMI
            h = payload.height_cm / 100
            row.bmi = round(kg / (h * h), 1)
        elif row.height_cm:
            h = row.height_cm / 100
            row.bmi = round(kg / (h * h), 1)

        if payload.body_composition:
            _apply_body(row, payload.body_composition)

        db.flush()

        # 记录活动日志，便于追溯
        detail = {
            "weight_kg": kg,
            "impedance_ohm": payload.impedance_ohm,
            "measured_at": (
                payload.measured_at.strftime("%Y-%m-%d %H:%M:%S")
                if payload.measured_at
                else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ),
            "source": "ble-frontend",
        }
        db.add(
            ActivityLog(
                user_id=current_user.id,
                action="create" if created else "update",
                module="health/body",
                resource_type="body",
                resource_id=row.id,
                summary=f"前端蓝牙同步体重 {kg} kg" + ("（含体成分）" if payload.body_composition else ""),
                detail=json.dumps(detail, ensure_ascii=False)[:2000],
                user_agent="web-bluetooth",
            )
        )
        db.commit()
        db.refresh(row)
        return row


router = crud_router(
    prefix="/health/body",
    tag="health-body",
    model=HealthBody,
    create_schema=BodyCreate,
    read_schema=BodyRead,
    order_by=HealthBody.record_date,
    date_column="record_date",
    stats_func=_body_stats,
    extra_routes=_register_extra_routes,
)