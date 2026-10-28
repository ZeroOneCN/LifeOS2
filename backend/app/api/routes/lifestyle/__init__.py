from fastapi import APIRouter

from app.api.routes.lifestyle import cards, items, overview, reports

router = APIRouter()
for sub in (items, cards, overview, reports):
    router.include_router(sub.router)