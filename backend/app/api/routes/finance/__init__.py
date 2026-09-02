from fastapi import APIRouter

from app.api.routes.finance import (
    debts,
    housing,
    loans,
    overview,
    planning,
    reminders,
    shopping,
    subscriptions,
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
    housing.router,
    subscriptions.router,
    loans.router,
    reminders.router,
    planning.router,
    debts.router,
):
    router.include_router(sub)