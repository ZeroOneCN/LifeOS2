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
for sub in (
    overview,
    vitals_sleep,
    fitness,
    diet,
    body,
    dashboard,
    steps,
    checkup,
    reports,
    medication,
):
    router.include_router(sub.router)
