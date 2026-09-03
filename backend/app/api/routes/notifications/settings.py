"""功能提醒开关路由：开关/提前天数/下发渠道统一管理。"""

import json

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models.notification_center import (
    FeatureReminderSetting,
    NotificationChannel,
)

router = APIRouter(prefix="/notifications/settings", tags=["notification-settings"])


class SettingIn(BaseModel):
    name: str
    category: str
    enabled: bool = False
    advance_days: int = 1
    channels: list[int] = []
    note: str | None = None


class SettingSearch:
    channels_labels: dict[int, str] = {}


def _channels_map(db: Session) -> dict[int, str]:
    rows = db.scalars(
        select(NotificationChannel).where(NotificationChannel.enabled.is_(True))
    ).all()
    return {c.id: c.name for c in rows}


def _to_dict(db: Session, s: FeatureReminderSetting) -> dict:
    try:
        ids = json.loads(s.channels or "[]")
    except Exception:
        ids = []
    ch_map = _channels_map(db)
    return {
        "id": s.id,
        "feature_key": s.feature_key,
        "name": s.name,
        "category": s.category,
        "enabled": s.enabled,
        "advance_days": s.advance_days,
        "channels": [int(i) for i in ids],
        "channel_names": [ch_map.get(int(i), str(i)) for i in ids],
        "note": s.note,
        "created_at": s.created_at,
        "updated_at": s.updated_at,
    }


@router.get("")
def list_settings(db: Session = Depends(get_db)):
    rows = db.scalars(
        select(FeatureReminderSetting).order_by(FeatureReminderSetting.id)
    ).all()
    return [_to_dict(db, s) for s in rows]


@router.get("/channels")
def enabled_channels(db: Session = Depends(get_db)):
    rows = db.scalars(
        select(NotificationChannel).where(NotificationChannel.enabled.is_(True))
    ).all()
    return [
        {"id": c.id, "name": c.name, "channel_type": c.channel_type} for c in rows
    ]


@router.put("/{item_id}")
def update_setting(item_id: int, payload: SettingIn, db: Session = Depends(get_db)):
    s = db.get(FeatureReminderSetting, item_id)
    if not s:
        raise HTTPException(status_code=404, detail="开关不存在")
    s.name = payload.name
    s.category = payload.category
    s.enabled = payload.enabled
    s.advance_days = payload.advance_days
    s.channels = json.dumps([int(i) for i in payload.channels])
    if payload.note is not None:
        s.note = payload.note
    db.commit()
    db.refresh(s)
    return _to_dict(db, s)