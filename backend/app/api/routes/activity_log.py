from collections import defaultdict
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.middleware.activity_logger import module_display_name
from app.models import ActivityLog, UserProfile
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
    current_user: UserProfile = Depends(get_current_user),
):
    """分页查询活动日志，支持按操作类型、模块、日期范围过滤。"""
    stmt = select(ActivityLog).where(ActivityLog.user_id == current_user.id)
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
def stats(
    days: int = Query(0, ge=0, le=36500),
    db: Session = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """统计活动日志：days=0 表示全部历史，>0 表示近 N 天。"""
    stmt = select(ActivityLog).where(ActivityLog.user_id == current_user.id)
    if days > 0:
        since = datetime.combine(date.today() - timedelta(days=days - 1), datetime.min.time())
        stmt = stmt.where(ActivityLog.created_at >= since)
    rows = db.scalars(stmt).all()

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
            {"module": m, "name": module_display_name(m), "count": n}
            for m, n in sorted(by_module.items(), key=lambda x: -x[1])
        ],
        "trend": [
            {"log_date": d.isoformat(), "count": n}
            for d, n in sorted(daily.items())
        ],
    }


@router.delete("")
def clear_logs(
    db: Session = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """清空当前用户的全部活动日志，返回删除记录数。"""
    result = db.execute(delete(ActivityLog).where(ActivityLog.user_id == current_user.id))
    db.commit()
    return {"deleted": result.rowcount or 0}
