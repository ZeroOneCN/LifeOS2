from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.api.knowledge.checkup import PANEL_PRESETS
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    HealthCheckup,
    HealthCheckupPanel,
    HealthCheckupPanelItem,
    HealthCheckupTemplate,
    UserProfile,
)
from app.schemas.health import (  # noqa: F401
    CheckupCreate,
    CheckupPanelCreate,
    CheckupPanelItem,
    CheckupPanelRead,
    CheckupRead,
    CheckupTemplateCreate,
    CheckupTemplateRead,
)

router = APIRouter()

RESULT_LABEL = {"normal": "正常", "high": "偏高", "low": "偏低"}


def _checkup_stats(db: Session, days: int, user_id: int) -> dict:
    since = date.today() - timedelta(days=days - 1)
    rows = db.scalars(
        select(HealthCheckup)
        .where(HealthCheckup.user_id == user_id)
        .where(HealthCheckup.check_date >= since)
        .order_by(HealthCheckup.check_date)
    ).all()

    by_item: dict[str, dict] = {}
    for r in rows:
        bucket = by_item.setdefault(
            r.item_name,
            {
                "item_name": r.item_name,
                "unit": r.unit,
                "reference_range": r.reference_range,
                "ref_low": r.ref_low,
                "ref_high": r.ref_high,
                "latest": None,
                "trend": [],
            },
        )
        bucket["unit"] = r.unit or bucket["unit"]
        bucket["reference_range"] = r.reference_range or bucket["reference_range"]
        bucket["ref_low"] = r.ref_low if r.ref_low is not None else bucket["ref_low"]
        bucket["ref_high"] = r.ref_high if r.ref_high is not None else bucket["ref_high"]
        bucket["trend"].append({"check_date": r.check_date, "value": r.value, "result": r.result})
        if bucket["latest"] is None or r.check_date > bucket["latest"]["check_date"]:
            bucket["latest"] = {"check_date": r.check_date, "value": r.value, "result": r.result}

    abnormal_items = [
        v["latest"]
        for v in by_item.values()
        if v["latest"] and v["latest"]["result"] and v["latest"]["result"] != "normal"
    ]
    abnormal_count = len(abnormal_items)

    # 状态分布
    status_counts = {"normal": 0, "high": 0, "low": 0}
    for v in by_item.values():
        if v["latest"] and v["latest"]["result"]:
            status_counts[v["latest"]["result"]] += 1

    return {
        "items": [
            {
                **v,
                "count": len(v["trend"]),
                "latest": v["latest"],
                "trend": v["trend"][-30:],
            }
            for v in by_item.values()
        ],
        "total_count": len(rows),
        "abnormal_count": abnormal_count,
        "status_counts": status_counts,
        "abnormal_items": abnormal_items,
        "status_label": RESULT_LABEL,
    }


# ---- 体检指标记录 CRUD ----
router = crud_router(
    prefix="/health/checkup",
    tag="health-checkup",
    model=HealthCheckup,
    create_schema=CheckupCreate,
    read_schema=CheckupRead,
    order_by=HealthCheckup.check_date,
    date_column="check_date",
    stats_func=_checkup_stats,
)


# ---- 体检标准模板 ----
# 注意：该子路由需在健康路由层优先注册，避免 /templates 被 /checkup/{item_id} 捕获
template_router = crud_router(
    prefix="/health/checkup/templates",
    tag="health-checkup-template",
    model=HealthCheckupTemplate,
    create_schema=CheckupTemplateCreate,
    read_schema=CheckupTemplateRead,
    order_by=HealthCheckupTemplate.item_name,
)


# ---- 体检组合模板（套餐） ----
def _panel_to_read(db: Session, panel: HealthCheckupPanel, user_id: int) -> dict:
    items = db.scalars(
        select(HealthCheckupPanelItem)
        .where(HealthCheckupPanelItem.user_id == user_id)
        .where(HealthCheckupPanelItem.panel_id == panel.id)
        .order_by(HealthCheckupPanelItem.item_name)
    ).all()
    return {
        "id": panel.id,
        "panel_name": panel.panel_name,
        "note": panel.note,
        "items": [
            {
                "item_name": it.item_name,
                "unit": it.unit,
                "ref_low": it.ref_low,
                "ref_high": it.ref_high,
                "reference_range": it.reference_range,
            }
            for it in items
        ],
    }


def _load_panels(db: Session, user_id: int) -> list[dict]:
    panels = db.scalars(
        select(HealthCheckupPanel)
        .where(HealthCheckupPanel.user_id == user_id)
        .order_by(HealthCheckupPanel.panel_name)
    ).all()
    return [_panel_to_read(db, p, user_id) for p in panels]


panel_router = APIRouter(prefix="/health/checkup/panels", tags=["health-checkup-panel"])


@panel_router.get("")
def list_panels(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    return _load_panels(db, user.id)


@panel_router.get("/presets")
def list_panel_presets():
    """内置常用体检组合（血常规/肝肾功能/血脂/血糖等），供快速选用。"""
    return PANEL_PRESETS


def _build_panel_items(payload) -> list[HealthCheckupPanelItem]:
    objs = []
    for it in payload.items:
        item = HealthCheckupPanelItem(
            item_name=it.item_name,
            unit=it.unit,
            ref_low=it.ref_low,
            ref_high=it.ref_high,
        )
        lo = f"{it.ref_low:g}" if it.ref_low is not None else ""
        hi = f"{it.ref_high:g}" if it.ref_high is not None else ""
        item.reference_range = f"{lo}~{hi}" if lo and hi else lo or hi or None
        objs.append(item)
    return objs


@panel_router.post("")
def create_panel(
    payload: CheckupPanelCreate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    panel = HealthCheckupPanel(panel_name=payload.panel_name.strip(), note=payload.note, user_id=user.id)
    db.add(panel)
    db.flush()
    for it in _build_panel_items(payload):
        it.panel_id = panel.id
        it.user_id = user.id
        db.add(it)
    db.commit()
    return _panel_to_read(db, panel, user.id)


@panel_router.put("/{panel_id}")
def update_panel(
    panel_id: int,
    payload: CheckupPanelCreate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    panel = db.scalar(
        select(HealthCheckupPanel).where(
            HealthCheckupPanel.id == panel_id,
            HealthCheckupPanel.user_id == user.id,
        )
    )
    if not panel:
        raise HTTPException(status_code=404, detail="组合不存在")
    panel.panel_name = payload.panel_name.strip()
    panel.note = payload.note
    # 重建明细（以提交为准）
    for old in db.scalars(
        select(HealthCheckupPanelItem).where(
            HealthCheckupPanelItem.user_id == user.id,
            HealthCheckupPanelItem.panel_id == panel_id,
        )
    ).all():
        db.delete(old)
    for it in _build_panel_items(payload):
        it.panel_id = panel_id
        it.user_id = user.id
        db.add(it)
    db.commit()
    return _panel_to_read(db, panel, user.id)


@panel_router.delete("/{panel_id}")
def delete_panel(
    panel_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    panel = db.scalar(
        select(HealthCheckupPanel).where(
            HealthCheckupPanel.id == panel_id,
            HealthCheckupPanel.user_id == user.id,
        )
    )
    if not panel:
        raise HTTPException(status_code=404, detail="组合不存在")
    for old in db.scalars(
        select(HealthCheckupPanelItem).where(
            HealthCheckupPanelItem.user_id == user.id,
            HealthCheckupPanelItem.panel_id == panel_id,
        )
    ).all():
        db.delete(old)
    db.delete(panel)
    db.commit()
    return {"ok": True}


# ---- 组合模板路由导出，交由健康路由层优先注册，避免 /panels 被 /checkup/{item_id} 捕获 ----