from fastapi import APIRouter

from app.api.routes.finance import (
    bills,
    debts,
    overview,
    planning,
    reminders,
    shopping,
    travel,
)

router = APIRouter()
for sub in (
    overview.router,
    shopping.platforms_router,
    shopping.ledgers_router,
    shopping.records_router,
    shopping.import_router,
    travel.router,
    bills.router,
    reminders.router,
    planning.router,
    debts.router,
):
    router.include_router(sub)