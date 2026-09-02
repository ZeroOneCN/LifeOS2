from collections import defaultdict
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import ActivityLog
from app.schemas.activity_log import ActivityLogRead
from app.schemas.health import PageOut

router = APIRouter(prefix="/activity-logs", tags=["activity_logs"])


@router.get("", response_model=PageOut[ActivityLogRead])
def list_logs(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    action: str | None = None,
    module: str | None = None,
    start: date | None = None,
    end: date | None = None,
    db: Session = Depends(get_db),
):
    """分页查询活动日志，支持按操作类型、模块、日期范围过滤。"""
    stmt = select(ActivityLog)
    if action:
        stmt = stmt.where(ActivityLog.action == action)
    if module:
        stmt = stmt.where(ActivityLog.module == module)
    if start:
        stmt = stmt.where(
            ActivityLog.created_at >= datetime.combine(start, datetime.min.time())
        )
    if end:
        stmt = stmt.where(
            ActivityLog.created_at <= datetime.combine(end, datetime.max.time())
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(
        stmt.order_by(ActivityLog.created_at.desc(), ActivityLog.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return PageOut(items=rows, total=total, page=page, page_size=page_size)


@router.get("/stats")
def stats(days: int = Query(30, ge=1, le=365), db: Session = Depends(get_db)):
    """统计近 N 天活动日志：总数/今日/按操作类型/按模块/按日趋势。"""
    since = datetime.combine(date.today() - timedelta(days=days - 1), datetime.min.time())
    rows = db.scalars(
        select(ActivityLog).where(ActivityLog.created_at >= since)
    ).all()

    daily: dict[date, int] = defaultdict(int)
    by_action: dict[str, int] = defaultdict(int)
    by_module: dict[str, int] = defaultdict(int)
    today = date.today()
    for r in rows:
        d = r.created_at.date()
        daily[d] += 1
        by_action[r.action] += 1
        by_module[r.module] += 1

    return {
        "total": len(rows),
        "today": sum(1 for r in rows if r.created_at.date() == today),
        "by_action": [
            {"action": a, "count": n}
            for a, n in sorted(by_action.items(), key=lambda x: -x[1])
        ],
        "by_module": [
            {"module": m, "count": n}
            for m, n in sorted(by_module.items(), key=lambda x: -x[1])
        ],
        "trend": [
            {"log_date": d.isoformat(), "count": n}
            for d, n in sorted(daily.items())
        ],
    }
