from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import models  # noqa: F401  确保所有模型注册到 Base.metadata
from app.api.routes import (
    activity_log,
    auth,
    finance,
    health,
    health_check,
    investment,
    lifestyle,
    notification,
    notifications,
    user,
)
from app.core.config import settings
from app.core.database import Base, SessionLocal, engine
from app.middleware.activity_logger import ActivityLoggerMiddleware
from app.services.notification.scheduler import start_scheduler, stop_scheduler
from app.services.notification.seed import ensure_seed


@asynccontextmanager
async def lifespan(app: FastAPI):
    """启动时自动创建数据库表（若不存在）并启动提醒调度器。"""
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        ensure_seed(db)
        db.commit()
    finally:
        db.close()
    start_scheduler()
    yield
    stop_scheduler()


app = FastAPI(title=settings.PROJECT_NAME, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(ActivityLoggerMiddleware)

app.include_router(health_check.router, prefix=settings.API_V1_PREFIX)
app.include_router(activity_log.router, prefix=settings.API_V1_PREFIX)
app.include_router(health.router, prefix=settings.API_V1_PREFIX)
app.include_router(finance.router, prefix=settings.API_V1_PREFIX)
app.include_router(lifestyle.router, prefix=settings.API_V1_PREFIX)
app.include_router(investment.router, prefix=settings.API_V1_PREFIX)
# 注意：通知中心扩展路由（/notifications/channels 等）必须先于通用 CRUD
# 路由（notification.router 的 /notifications/{item_id}）注册，否则会被捕获。
app.include_router(notifications.router, prefix=settings.API_V1_PREFIX)
app.include_router(notification.router, prefix=settings.API_V1_PREFIX)
app.include_router(user.router, prefix=settings.API_V1_PREFIX)
app.include_router(auth.router, prefix=settings.API_V1_PREFIX)


@app.get("/")
def root() -> dict[str, str]:
    return {"message": f"Welcome to {settings.PROJECT_NAME}"}
