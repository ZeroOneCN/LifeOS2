from fastapi import APIRouter

from app.api.routes.lifestyle import cards, items, overview, reports, todos

router = APIRouter()
for sub in (items, cards, todos, overview, reports):
    router.include_router(sub.router)