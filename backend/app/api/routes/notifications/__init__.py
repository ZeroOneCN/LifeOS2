"""通知中心扩展路由聚合：渠道/模板/开关/发送日志/测试/扫描。"""

from fastapi import APIRouter

from app.api.routes.notifications import (
    channels,
    scan,
    send_log,
    settings,
    templates,
    test,
)

router = APIRouter()
for sub in (
    channels.router,
    templates.router,
    settings.router,
    send_log.router,
    test.router,
    scan.router,
):
    router.include_router(sub)