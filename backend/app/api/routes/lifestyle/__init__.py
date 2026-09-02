from fastapi import APIRouter

from app.api.routes.lifestyle import items, schedule, sim_cards, todos

router = APIRouter()
for sub in (items, sim_cards, todos, schedule):
    router.include_router(sub.router)
