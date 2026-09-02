from fastapi import APIRouter

from app.api.routes.finance import (
    bills,
    overview,
    planning,
    purchases,
    reminders,
    travel,
)

router = APIRouter()
for sub in (
    overview,
    purchases,
    travel,
    bills,
    reminders,
    planning,
):
    router.include_router(sub.router)
