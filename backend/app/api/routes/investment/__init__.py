from fastapi import APIRouter

from app.api.routes.investment import forex, funds, overview, reports

router = APIRouter()
for sub in (overview, forex, funds, reports):
    router.include_router(sub.router)