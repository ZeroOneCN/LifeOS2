from fastapi import APIRouter

router = APIRouter(tags=["health-check"])


@router.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}
