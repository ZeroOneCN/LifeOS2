from contextlib import asynccontextmanager
import os
import sys

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.engine import make_url

from app import models  # noqa: F401  确保所有模型注册到 Base.metadata
from app.api.routes import (
    activity_log,
    auth,
    backup,
    finance,
    health,
    health_check,
    investment,
    lifestyle,
    login_audit,
    motivation,
    notification,
    notifications,
    site_config,
    user,
)
from app.core.config import settings
from app.core.database import SessionLocal
from app.core.errors import register_exception_handlers
from app.core.logging_config import print_startup_banner, setup_logging
from app.middleware.activity_logger import ActivityLoggerMiddleware
from app.middleware.request_id import RequestIdMiddleware
from app.services.notification.scheduler import start_scheduler, stop_scheduler
from app.services.notification.seed import ensure_seed
from app.services.backup_scheduler import (
    start_scheduler as start_backup_scheduler,
    stop_scheduler as stop_backup_scheduler,
)
from app.services.report_scheduler import (
    start_scheduler as start_report_scheduler,
    stop_scheduler as stop_report_scheduler,
)
from app.services.scale_collector import scale_collector

# 日志配置在应用导入时完成，保证启动阶段与请求阶段格式一致
setup_logging()


def _listen_address() -> tuple[str, int]:
    """解析启动监听地址：优先环境变量，其次 uvicorn 命令行参数，默认 127.0.0.1:8000。

    kwargs:
        无。

    Returns:
        (host, port) 二元组；非法端口时回退 8000。
    """
    host = os.getenv("APP_HOST", "127.0.0.1")
    port = 8000
    try:
        port = int(os.getenv("APP_PORT", "8000"))
    except ValueError:
        port = 8000

    args = sys.argv[1:]
    for index, arg in enumerate(args):
        if arg == "--host" and index + 1 < len(args):
            host = args[index + 1]
        elif arg.startswith("--host="):
            host = arg.split("=", 1)[1]
        elif arg == "--port" and index + 1 < len(args):
            try:
                port = int(args[index + 1])
            except ValueError:
                pass
        elif arg.startswith("--port="):
            try:
                port = int(arg.split("=", 1)[1])
            except ValueError:
                pass
    return host, port


def _safe_database_target(url_text: str) -> str:
    """生成不含密码的数据库目标描述。

    Args:
        url_text: SQLAlchemy 数据库连接串。

    Returns:
        形如 ``mysql+pymysql://root@127.0.0.1:3307/lifeos2`` 的脱敏描述；解析失败返回 unknown。
    """
    try:
        url = make_url(url_text)
    except Exception:  # noqa: BLE001 - 仅用于展示，解析失败不应阻断启动
        return "unknown"
    port = f":{url.port}" if url.port else ""
    return f"{url.drivername}://{url.username or '-'}@{url.host or '-'}{port}/{url.database or '-'}"


def _job_summary() -> list[str]:
    """生成定时任务清单概要（供启动横幅展示）。

    kwargs:
        无。

    Returns:
        每个任务一行的概要文本列表。
    """
    return [
        f"notify_daily_scan         每日 {settings.NOTIFY_SCAN_TIME}",
        "notify_overdue_hourly     每小时整点",
        "phone_billing_settle      每日 00:30",
        "cleanup_expired_sessions  每日 03:00",
        "backup_scheduled_scan     每分钟",
        f"monthly_report_generate   每月 1 日 {settings.MONTHLY_REPORT_TIME}",
    ]


@asynccontextmanager
async def lifespan(app: FastAPI):
    """启动时初始化基础数据并启动提醒调度器与体重秤采集。

    数据库结构由 Alembic 迁移负责（启动前请先执行 ``python -m alembic upgrade head``），
    应用启动阶段不再建表、不再补建索引。
    """
    db = SessionLocal()
    try:
        ensure_seed(db)
        db.commit()
    finally:
        db.close()
    start_scheduler()
    start_backup_scheduler()
    start_report_scheduler()

    host, port = _listen_address()
    print_startup_banner(
        project_name=settings.PROJECT_NAME,
        environment=settings.ENVIRONMENT,
        host=host,
        port=port,
        api_prefix=settings.API_V1_PREFIX,
        database=_safe_database_target(settings.DATABASE_URL),
        jobs=_job_summary(),
    )

    await scale_collector.start()
    yield
    await scale_collector.stop()
    stop_report_scheduler()
    stop_backup_scheduler()
    stop_scheduler()


app = FastAPI(title=settings.PROJECT_NAME, lifespan=lifespan)
register_exception_handlers(app)

app.add_middleware(
    CORSMiddleware,
    # 局域网/开发模式允许任意来源（配合 allow_credentials 使用 allow_origin_regex），
    # 否则仅放行 CORS_ORIGINS 白名单
    allow_origins=[] if settings.CORS_ALLOW_ALL else settings.CORS_ORIGINS,
    allow_origin_regex=".*" if settings.CORS_ALLOW_ALL else None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(ActivityLoggerMiddleware)
# request id 中间件最后添加 => 位于最外层，确保活动日志及下游异常都能带上 request id
app.add_middleware(RequestIdMiddleware)

app.include_router(health_check.router, prefix=settings.API_V1_PREFIX)
app.include_router(activity_log.router, prefix=settings.API_V1_PREFIX)
app.include_router(health.router, prefix=settings.API_V1_PREFIX)
app.include_router(finance.router, prefix=settings.API_V1_PREFIX)
app.include_router(lifestyle.router, prefix=settings.API_V1_PREFIX)
app.include_router(investment.router, prefix=settings.API_V1_PREFIX)
app.include_router(motivation.router, prefix=settings.API_V1_PREFIX)
# 注意：通知中心扩展路由（/notifications/channels 等）必须先于通用 CRUD
# 路由（notification.router 的 /notifications/{item_id}）注册，否则会被捕获。
app.include_router(notifications.router, prefix=settings.API_V1_PREFIX)
app.include_router(notification.router, prefix=settings.API_V1_PREFIX)
app.include_router(user.router, prefix=settings.API_V1_PREFIX)
app.include_router(auth.router, prefix=settings.API_V1_PREFIX)
app.include_router(login_audit.router, prefix=settings.API_V1_PREFIX)
app.include_router(backup.router, prefix=settings.API_V1_PREFIX)
app.include_router(site_config.router, prefix=settings.API_V1_PREFIX)


@app.get("/")
def root() -> dict[str, str]:
    return {"message": f"Welcome to {settings.PROJECT_NAME}"}
