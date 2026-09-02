from fastapi import APIRouter

from app.api.routes.health import (
    checkup,
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
    steps,
    checkup,
    reports,
    medication,
):
    router.include_router(sub.router)
