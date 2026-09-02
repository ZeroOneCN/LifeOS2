from fastapi import APIRouter

from app.api.routes.health import (
    body,
    checkup,
    dashboard,
    diet,
    fitness,
    medication,
    overview,
    reports,
    steps,
    vitals_sleep,
)

router = APIRouter()
# 固定子路由（template/panel）需在 checkup 的 /{item_id} 之前注册，否则会被捕获
for sub in (
    overview,
    vitals_sleep,
    fitness,
    diet,
    body,
    dashboard,
    steps,
    checkup.template_router,
    checkup.panel_router,
    checkup,
    reports,
    medication,
):
    router.include_router(getattr(sub, "router", sub))
