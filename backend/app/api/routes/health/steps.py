from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.crud import crud_router, days_since
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import HealthStepSetting, HealthSteps, UserProfile
from app.schemas.health import StepSettingCreate, StepSettingRead, StepsCreate, StepsRead

router = APIRouter()

# 每日应有的完整时间段（16 个整点小时段 + 1 个全天最终段），用于每日步数完整性检测
EXPECTED_PERIODS = [
    "08-09",
    "09-10",
    "10-11",
    "11-12",
    "12-13",
    "13-14",
    "14-15",
    "15-16",
    "16-17",
    "17-18",
    "18-19",
    "19-20",
    "20-21",
    "21-22",
    "22-23",
    "23-24",
    "full",
]


def _get_setting(db: Session, user_id: int) -> HealthStepSetting:
    setting = db.scalar(
        select(HealthStepSetting).where(HealthStepSetting.user_id == user_id)
    )
    if not setting:
        setting = HealthStepSetting(stride_cm=70.0, user_id=user_id)
        db.add(setting)
        db.commit()
        db.refresh(setting)
    return setting


def _register_fixed(router) -> None:
    """注册固定静态路由，需在动态路由 /{item_id} 之前。"""

    @router.get("/settings", response_model=StepSettingRead)
    def get_settings(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        return _get_setting(db, user.id)

    @router.put("/settings", response_model=StepSettingRead)
    def update_settings(
        payload: StepSettingCreate,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        setting = _get_setting(db, user.id)
        setting.stride_cm = payload.stride_cm
        # 步幅变更后，按新步幅实时重算所有记录的距离
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .where(HealthSteps.steps.isnot(None))
        ).all()
        for r in rows:
            r.distance_km = round(r.steps * payload.stride_cm / 100000, 2)
        db.commit()
        db.refresh(setting)
        return setting

    @router.get("/monthly")
    def monthly_stats(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """按自然月统计步数（近 12 个月）。每月 = 该月每天最大值之和。"""
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .order_by(HealthSteps.record_date)
        ).all()
        # 先按 (年-月, 日) 取每天最大值
        day_max: dict[tuple[str, date], dict] = {}
        for r in rows:
            key_month = r.record_date.strftime("%Y-%m")
            dk = (key_month, r.record_date)
            steps = r.steps or 0
            cur = day_max.get(dk)
            if cur is None or steps > cur["steps"]:
                day_max[dk] = {
                    "steps": steps,
                    "distance_km": r.distance_km or 0,
                    "calories": r.calories or 0,
                }
        by_month: dict[str, dict] = defaultdict(
            lambda: {"steps": 0, "distance_km": 0.0, "calories": 0.0, "days": set()}
        )
        for (key_month, rd), dm in day_max.items():
            by_month[key_month]["steps"] += dm["steps"]
            by_month[key_month]["distance_km"] += dm["distance_km"]
            by_month[key_month]["calories"] += dm["calories"]
            by_month[key_month]["days"].add(rd)
        return {
            "months": [
                {
                    "month": k,
                    "steps": v["steps"],
                    "distance_km": round(v["distance_km"], 2),
                    "calories": round(v["calories"], 1),
                    "days": len(v["days"]),
                }
                for k, v in sorted(by_month.items())[-12:]
            ]
        }

    @router.get("/daily-summary")
    def daily_summary(
        year: int | None = Query(None),
        month: int | None = Query(None),
        page: int = Query(1, ge=1),
        page_size: int = Query(8, ge=1, le=31),
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """指定月份的每日步数汇总（按天累加所有时间段），默认当月，按页返回（默认每页 8 天）。"""
        today = date.today()
        y = year or today.year
        m = month or today.month
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .where(func.month(HealthSteps.record_date) == m)
            .where(func.year(HealthSteps.record_date) == y)
            .order_by(HealthSteps.record_date)
        ).all()
        by_day: dict[date, dict] = {}
        for r in rows:
            steps = r.steps or 0
            d = by_day.get(r.record_date)
            if d is None:
                d = by_day[r.record_date] = {
                    "date": r.record_date,
                    "steps": 0,
                    "distance_km": 0.0,
                    "calories": 0.0,
                    "count": 0,
                }
            # 每日取最大值（同天多个时间段是累计序列，取最大的即当天代表值）
            if steps > d["steps"]:
                by_day[r.record_date] = {
                    **d,
                    "steps": steps,
                    "distance_km": r.distance_km or 0,
                    "calories": r.calories or 0,
                }
            by_day[r.record_date]["count"] += 1
        days = sorted(by_day.items(), key=lambda x: x[0], reverse=True)
        total = len(days)
        start = (page - 1) * page_size
        current = days[start:start + page_size]
        return {
            "month": f"{y}-{m:02d}",
            "items": [
                {
                    "record_date": v["date"],
                    "steps": v["steps"],
                    "distance_km": round(v["distance_km"], 2),
                    "calories": round(v["calories"], 1),
                    "count": v["count"],
                }
                for d, v in current
            ],
            "total": total,
            "page": page,
            "page_size": page_size,
        }

    @router.get("/incomplete-days")
    def incomplete_days(
        days: int = Query(14, ge=1, le=90),
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """检测每日步数是否录满 EXPECTED_PERIODS（17 个时间段），返回缺失日期供前端弹窗提醒补录。

        判定口径：同一天已录入的不同时间段数量 < 17 即视为缺失。仅扫描「昨天及更早」的日期，
        且不早于用户首个记录日期，避免对进行中的当天与启用前的空白期误报。
        """
        today = date.today()
        first_date = db.scalar(
            select(func.min(HealthSteps.record_date)).where(HealthSteps.user_id == user.id)
        )
        empty = {"expected": len(EXPECTED_PERIODS), "days": [], "total": 0}
        if first_date is None:
            return empty
        start = max(today - timedelta(days=days), first_date)
        if start >= today:
            return empty
        rows = db.execute(
            select(HealthSteps.record_date, HealthSteps.period)
            .where(HealthSteps.user_id == user.id)
            .where(HealthSteps.record_date >= start)
            .where(HealthSteps.record_date < today)
            .distinct()
        ).all()
        recorded: dict[date, set[str]] = defaultdict(set)
        for record_date, period in rows:
            recorded[record_date].add(period)
        # 从昨天往前逐日比对，最新缺失排在最前
        result = []
        cursor = today - timedelta(days=1)
        while cursor >= start:
            got = recorded.get(cursor, set())
            missing = [p for p in EXPECTED_PERIODS if p not in got]
            if missing:
                result.append(
                    {"record_date": cursor, "recorded": len(got), "missing": missing}
                )
            cursor -= timedelta(days=1)
        return {"expected": len(EXPECTED_PERIODS), "days": result, "total": len(result)}

    @router.get("/month-detail")
    def month_detail(
        year: int | None = Query(None),
        month: int | None = Query(None),
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        """返回指定月份的全部步数明细（每条含 record_date/period/steps），供前端聚合趋势/分布/对比。"""
        today = date.today()
        y = year or today.year
        m = month or today.month
        rows = db.scalars(
            select(HealthSteps)
            .where(HealthSteps.user_id == user.id)
            .where(func.year(HealthSteps.record_date) == y)
            .where(func.month(HealthSteps.record_date) == m)
            .order_by(HealthSteps.record_date, HealthSteps.id)
        ).all()
        return {
            "month": f"{y}-{m:02d}",
            "days": [
                {
                    "record_date": r.record_date,
                    "period": r.period,
                    "steps": r.steps or 0,
                }
                for r in rows
            ],
        }


def _steps_stats(db: Session, days: int, user_id: int) -> dict:
    since = days_since(days)
    stmt = select(HealthSteps).where(HealthSteps.user_id == user_id)
    if since is not None:
        stmt = stmt.where(HealthSteps.record_date >= since)
    rows = db.scalars(
        stmt.order_by(HealthSteps.record_date, HealthSteps.id)
    ).all()

    by_day: dict[date, dict] = {}
    by_period: dict[str, int] = defaultdict(int)
    for r in rows:
        steps = r.steps or 0
        d = by_day.get(r.record_date)
        # 每日取最大值（同天多时段累计序列）
        if d is None or steps > d["steps"]:
            by_day[r.record_date] = {
                "steps": steps,
                "distance_km": r.distance_km or 0,
                "calories": r.calories or 0,
            }
        by_period[r.period] += steps

    steps_list = [by_day[d]["steps"] for d in by_day]
    total_steps = sum(steps_list)

    return {
        "trend": [
            {
                "record_date": d,
                "steps": v["steps"],
                "distance_km": round(v["distance_km"], 2),
                "calories": round(v["calories"], 1),
            }
            for d, v in sorted(by_day.items())
        ],
        "by_period": [
            {"period": k, "steps": v}
            for k, v in sorted(by_period.items(), key=lambda x: x[0])
        ],
        "avg_steps": round(total_steps / len(by_day)) if by_day else None,
        "max_steps": max(steps_list) if steps_list else None,
        "total_steps": total_steps,
        "record_count": len(rows),
    }


router = crud_router(
    prefix="/health/steps",
    tag="health-steps",
    model=HealthSteps,
    create_schema=StepsCreate,
    read_schema=StepsRead,
    order_by=[HealthSteps.record_date, HealthSteps.period],
    date_column="record_date",
    stats_func=_steps_stats,
    extra_routes=_register_fixed,
    # 同一天同一时间段只允许一条记录，新增/编辑均做业务唯一性校验，防止网络重试堆积导致重复入库
    conflict_fields=["record_date", "period"],
    conflict_msg="该日期已存在相同时间段的步数记录，请勿重复添加",
)