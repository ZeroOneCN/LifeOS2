"""通知测试发送路由。"""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.models.notification_center import NotificationChannel, NotificationSendLog
from app.schemas.notification_center import TestSendPayload
from app.services.notification.channels import TEST_CONTENT, TEST_TITLE, send_to_channel

router = APIRouter(prefix="/notifications", tags=["notification-test"])


@router.post("/test-send")
def test_send(
    payload: TestSendPayload,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ch = db.scalar(
        select(NotificationChannel).where(
            NotificationChannel.id == payload.channel_id,
            NotificationChannel.user_id == current_user.id,
        )
    )
    if not ch:
        raise HTTPException(status_code=404, detail="渠道不存在")
    if not ch.enabled:
        raise HTTPException(status_code=400, detail="渠道未启用")
    title = payload.title or TEST_TITLE
    content = payload.content or TEST_CONTENT
    ok, result = send_to_channel(ch, title, content)
    log = NotificationSendLog(
        user_id=current_user.id,
        notification_id=None,
        channel_type=ch.channel_type,
        channel_id=ch.id,
        status="sent" if ok else "failed",
        error=None if ok else result,
        sent_at=datetime.now(),
    )
    db.add(log)
    db.commit()
    return {"ok": ok, "message": result}