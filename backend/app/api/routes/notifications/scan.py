"""立即触发一次提醒扫描。"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.services.notification.scanner import scan_all
from app.services.notification.seed import ensure_seed

router = APIRouter(prefix="/notifications", tags=["notification-scan"])


@router.post("/scan")
def run_scan_now(db: Session = Depends(get_db)):
    ensure_seed(db)
    summary = scan_all(db)
    return summary