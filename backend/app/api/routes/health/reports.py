from datetime import date, timedelta

from fastapi import APIRouter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.models import HealthReport
from app.schemas.health import ReportCreate, ReportRead

router = APIRouter()


def _reports_stats(db: Session, days: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthReport)
        .where(HealthReport.report_date >= since)
        .order_by(HealthReport.report_date.desc())
    ).all()

    return {
        "recent": [
            {
                "id": r.id,
                "report_date": r.report_date,
                "title": r.title,
                "summary": r.summary,
            }
            for r in rows[:5]
        ],
        "total_count": len(rows),
    }


router = crud_router(
    prefix="/health/reports",
    tag="health-reports",
    model=HealthReport,
    create_schema=ReportCreate,
    read_schema=ReportRead,
    order_by=HealthReport.report_date,
    date_column="report_date",
    stats_func=_reports_stats,
)
