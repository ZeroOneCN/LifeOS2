"""通知渠道配置路由。"""

import json

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.models.notification_center import NotificationChannel
from app.services.notification.channels import CHANNEL_LABELS
from app.services.notification.crypto import (
    decrypt_config,
    encrypt_config,
    mask_config,
)

router = APIRouter(prefix="/notifications/channels", tags=["notification-channels"])


class ChannelIn(BaseModel):
    channel_type: str
    name: str
    enabled: bool = True
    recipients: str | None = None
    note: str | None = None
    config: dict = Field(default_factory=dict)


def _to_dict(ch: NotificationChannel) -> dict:
    try:
        config = json.loads(ch.config or "{}")
    except Exception:
        config = {}
    return {
        "id": ch.id,
        "channel_type": ch.channel_type,
        "channel_type_label": CHANNEL_LABELS.get(ch.channel_type, ch.channel_type),
        "name": ch.name,
        "enabled": ch.enabled,
        "recipients": ch.recipients,
        "note": ch.note,
        "config": mask_config(ch.channel_type, config),
        "created_at": ch.created_at,
        "updated_at": ch.updated_at,
    }


@router.get("")
def list_channels(
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.scalars(
        select(NotificationChannel)
        .where(NotificationChannel.user_id == current_user.id)
        .order_by(NotificationChannel.id)
    ).all()
    return [_to_dict(c) for c in rows]


@router.post("", status_code=201)
def create_channel(
    payload: ChannelIn,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    config = encrypt_config(payload.channel_type, dict(payload.config))
    ch = NotificationChannel(
        user_id=current_user.id,
        channel_type=payload.channel_type,
        name=payload.name,
        enabled=payload.enabled,
        recipients=payload.recipients,
        note=payload.note,
        config=json.dumps(config, ensure_ascii=False),
    )
    db.add(ch)
    db.commit()
    db.refresh(ch)
    return _to_dict(ch)


@router.put("/{item_id}")
def update_channel(
    item_id: int,
    payload: ChannelIn,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ch = db.scalar(
        select(NotificationChannel).where(
            NotificationChannel.id == item_id,
            NotificationChannel.user_id == current_user.id,
        )
    )
    if not ch:
        raise HTTPException(status_code=404, detail="渠道不存在")
    try:
        old = json.loads(ch.config or "{}")
    except Exception:
        old = {}
    old = decrypt_config(ch.channel_type, old)
    new = dict(payload.config)
    # 敏感字段未变（掩码或缺失）时沿用旧值，避免覆盖
    for key, val in list(new.items()):
        if val in ("******", "", None):
            new.pop(key, None)
    merged = {**old, **new}
    merged_enc = encrypt_config(channel_type=ch.channel_type, config=merged)
    ch.name = payload.name
    ch.enabled = payload.enabled
    ch.recipients = payload.recipients
    ch.note = payload.note
    ch.config = json.dumps(merged_enc, ensure_ascii=False)
    db.commit()
    db.refresh(ch)
    return _to_dict(ch)


@router.delete("/{item_id}", status_code=204)
def delete_channel(
    item_id: int,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    ch = db.scalar(
        select(NotificationChannel).where(
            NotificationChannel.id == item_id,
            NotificationChannel.user_id == current_user.id,
        )
    )
    if not ch:
        raise HTTPException(status_code=404, detail="渠道不存在")
    db.delete(ch)
    db.commit()
    return None