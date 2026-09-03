"""通知模板路由：查看/编辑/重置默认模板。"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.models.notification_center import NotificationTemplate
from app.services.notification.templates import get_default

router = APIRouter(prefix="/notifications/templates", tags=["notification-templates"])


class TemplateIn(BaseModel):
    name: str
    title_template: str
    content_template: str
    note: str | None = None


@router.get("")
def list_templates(
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.scalars(
        select(NotificationTemplate)
        .where(NotificationTemplate.user_id == current_user.id)
        .order_by(NotificationTemplate.id)
    ).all()
    return rows


@router.put("/{item_id}")
def update_template(
    item_id: int,
    payload: TemplateIn,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    tpl = db.scalar(
        select(NotificationTemplate).where(
            NotificationTemplate.id == item_id,
            NotificationTemplate.user_id == current_user.id,
        )
    )
    if not tpl:
        raise HTTPException(status_code=404, detail="模板不存在")
    tpl.name = payload.name
    tpl.title_template = payload.title_template
    tpl.content_template = payload.content_template
    if payload.note is not None:
        tpl.note = payload.note
    db.commit()
    db.refresh(tpl)
    return tpl


@router.post("/{item_id}/reset")
def reset_template(
    item_id: int,
    current_user: UserProfile = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    tpl = db.scalar(
        select(NotificationTemplate).where(
            NotificationTemplate.id == item_id,
            NotificationTemplate.user_id == current_user.id,
        )
    )
    if not tpl:
        raise HTTPException(status_code=404, detail="模板不存在")
    title, content = get_default(tpl.source)
    tpl.title_template = title
    tpl.content_template = content
    db.commit()
    db.refresh(tpl)
    return tpl