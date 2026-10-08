from collections import defaultdict
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_admin
from app.models import LoginAudit, UserProfile
from app.schemas.health import PageOut
from app.schemas.login_audit import LoginAuditRead

router = APIRouter(prefix="/login-audits", tags=["login_audits"])


@router.get("", response_model=PageOut[LoginAuditRead])
def list_audits(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    result: str | None = None,
    account: str | None = None,
    ip: str | None = None,
    start: date | None = None,
    end: date | None = None,
    db: Session = Depends(get_db),
    current_user: UserProfile = Depends(get_current_admin),
):
    """分页查询登录审计记录，支持按结果/账号/IP/日期范围过滤。仅管理员。"""
    stmt = select(LoginAudit)
    if result:
        stmt = stmt.where(LoginAudit.result == result)
    if account:
        stmt = stmt.where(LoginAudit.account.like(f"%{account}%"))
    if ip:
        stmt = stmt.where(LoginAudit.ip_address == ip)
    if start:
        stmt = stmt.where(
            LoginAudit.created_at >= datetime.combine(start, datetime.min.time())
        )
    if end:
        stmt = stmt.where(
            LoginAudit.created_at <= datetime.combine(end, datetime.max.time())
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(
        stmt.order_by(LoginAudit.created_at.desc(), LoginAudit.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return PageOut(items=rows, total=total, page=page, page_size=page_size)


@router.get("/stats")
def stats(
    days: int = Query(30, ge=1, le=365),
    db: Session = Depends(get_db),
    current_user: UserProfile = Depends(get_current_admin),
):
    """统计近 N 天登录审计：总数/今日/按结果/按 IP(Top10)/趋势/暴力破解嫌疑 IP。仅管理员。"""
    since = datetime.combine(
        date.today() - timedelta(days=days - 1), datetime.min.time()
    )
    rows = db.scalars(
        select(LoginAudit).where(LoginAudit.created_at >= since)
    ).all()

    daily: dict[date, int] = defaultdict(int)
    by_result: dict[str, int] = defaultdict(int)
    by_ip: dict[str | None, int] = defaultdict(int)
    today = date.today()
    for r in rows:
        d = r.created_at.date()
        daily[d] += 1
        by_result[r.result] += 1
        by_ip[r.ip_address] += 1

    # 暴力破解嫌疑 IP：近窗口内同 IP 失败次数 ≥ 阈值
    window_since = datetime.now() - timedelta(
        minutes=settings.BRUTE_FORCE_WINDOW_MINUTES
    )
    brute_rows = db.execute(
        select(
            LoginAudit.ip_address,
            func.count().label("cnt"),
            func.max(LoginAudit.created_at).label("last_at"),
            func.count(LoginAudit.account.distinct()).label("account_cnt"),
        )
        .where(
            LoginAudit.created_at >= window_since,
            LoginAudit.result.in_(["fail", "locked"]),
            LoginAudit.ip_address.isnot(None),
        )
        .group_by(LoginAudit.ip_address)
        .having(func.count() >= settings.BRUTE_FORCE_THRESHOLD)
        .order_by(func.count().desc())
    ).all()
    brute_force_ips = [
        {
            "ip": row.ip_address,
            "fail_count": row.cnt,
            "account_count": row.account_cnt,
            "last_attempt": row.last_at.isoformat() if row.last_at else None,
        }
        for row in brute_rows
    ]

    return {
        "total": len(rows),
        "today": sum(1 for r in rows if r.created_at.date() == today),
        "by_result": [
            {"result": k, "count": v}
            for k, v in sorted(by_result.items(), key=lambda x: -x[1])
        ],
        "by_ip": [
            {"ip": k or "未知", "count": v}
            for k, v in sorted(by_ip.items(), key=lambda x: -x[1])[:10]
        ],
        "trend": [
            {"log_date": d.isoformat(), "count": n}
            for d, n in sorted(daily.items())
        ],
        "brute_force_ips": brute_force_ips,
        "brute_force_window_minutes": settings.BRUTE_FORCE_WINDOW_MINUTES,
        "brute_force_threshold": settings.BRUTE_FORCE_THRESHOLD,
    }
