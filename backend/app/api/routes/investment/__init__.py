from fastapi import APIRouter

from app.api.routes.investment import forex

router = APIRouter()
for sub in (forex,):
    router.include_router(sub.router)
