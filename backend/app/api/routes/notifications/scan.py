"""立即触发一次提醒扫描。"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.services.notification.scanner import scan_all
from app.services.notification.seed import ensure_seed

router = APIRouter(prefix="/notifications", tags=["notification-scan"])


@router.post("/scan")
def run_scan_now(
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ensure_seed(db, user_id=current_user.id)
    summary = scan_all(db, user_id=current_user.id)
    return summary