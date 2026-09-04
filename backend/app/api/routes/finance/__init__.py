from fastapi import APIRouter

from app.api.routes.finance import (
    currencies,
    debts,
    housing,
    investments,
    loans,
    memos,
    overview,
    planning,
    reminders,
    rent,
    reports,
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
    rent.router,
    subscriptions.router,
    subscriptions.subscription_categories_router,
    loans.router,
    reminders.router,
    planning.router,
    debts.router,
    investments.router,
    memos.router,
    currencies.router,
    reports.router,
):
    router.include_router(sub)