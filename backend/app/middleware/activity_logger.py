import json

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import settings
from app.core.database import SessionLocal
from app.models import ActivityLog

API_PREFIX = settings.API_V1_PREFIX

# 模块路径（去前缀、去ID后的子路径） -> 中文名
MODULE_NAMES = {
    "health/vitals-sleep": "睡眠体征",
    "health/fitness": "健身运动",
    "health/diet": "饮食记录",
    "health/body": "体重记录",
    "health/steps": "步数统计",
    "health/checkup": "体检指标",
    "health/reports": "健康报告",
    "health/medication": "用药跟踪",
    "health/medication/purchases": "购药记录",
    "health/medication/stocks": "药品库存",
    "finance/purchases": "购买记录",
    "finance/travel": "旅行开支",
    "finance/bills": "账单管理",
    "finance/reminders": "账单提醒",
    "finance/planning": "财务规划",
    "finance/debts": "债务管理",
    "lifestyle/items": "物品追踪",
    "lifestyle/sim-cards": "卡片管理",
    "lifestyle/todos": "待办清单",
    "lifestyle/schedule": "日程管理",
    "investment/forex": "外汇交易",
    "notifications": "通知中心",
    "user/profile": "个人资料",
    "user/settings": "账号设置",
}

ACTION_NAMES = {"create": "新增", "update": "更新", "delete": "删除"}

MAX_DETAIL = 2000  # 详情字段最大保留长度


class ActivityLoggerMiddleware:
    """纯 ASGI 中间件：拦截 /api/v1 下的写操作（POST/PUT/DELETE），自动写入活动日志。"""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        method = scope["method"]
        path = scope["path"]
        should_log = (
            method in ("POST", "PUT", "DELETE")
            and path.startswith(API_PREFIX)
            and not path.startswith(f"{API_PREFIX}/activity-logs")
        )

        if not should_log:
            await self.app(scope, receive, send)
            return

        # 缓冲请求体，同时透传给下游（保证路由仍能读取 body）
        body = bytearray()
        status_holder: dict[str, int] = {"status": 0}
        resp_body = bytearray()

        async def buffered_receive() -> Message:
            message = await receive()
            if message["type"] == "http.request":
                body.extend(message.get("body", b""))
            return message

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                status_holder["status"] = message["status"]
            elif message["type"] == "http.response.body":
                resp_body.extend(message.get("body", b""))
            await send(message)

        await self.app(scope, buffered_receive, send_wrapper)

        # 仅记录成功（2xx/3xx）的写操作
        status = status_holder["status"]
        if not (200 <= status < 400):
            return

        ip = None
        client = scope.get("client")
        if client and client[0]:
            ip = client[0]

        req_data = self._parse_json(body)
        resp_data = self._parse_json(resp_body)

        action = {"POST": "create", "PUT": "update", "DELETE": "delete"}[method]
        segments = [s for s in path[len(API_PREFIX) :].strip("/").split("/")]
        non_numeric = [s for s in segments if not s.isdigit()]
        module = "/".join(non_numeric)
        resource_type = non_numeric[-1] if non_numeric else module

        resource_id: int | None = None
        if method == "DELETE":
            if segments and segments[-1].isdigit():
                resource_id = int(segments[-1])
        else:
            if isinstance(resp_data, dict):
                rid = resp_data.get("id")
                if isinstance(rid, int):
                    resource_id = rid
            if resource_id is None and segments and segments[-1].isdigit():
                resource_id = int(segments[-1])

        summary = self._build_summary(action, module, resource_id)
        detail = None
        if action == "delete":
            detail = f"删除 {module} 记录，ID={resource_id}"
        elif req_data is not None:
            detail = json.dumps(req_data, ensure_ascii=False)
        elif resp_data is not None:
            detail = json.dumps(resp_data, ensure_ascii=False)
        if detail and len(detail) > MAX_DETAIL:
            detail = detail[:MAX_DETAIL] + "…"

        db = SessionLocal()
        try:
            db.add(
                ActivityLog(
                    action=action,
                    module=module,
                    resource_type=resource_type,
                    resource_id=resource_id,
                    summary=summary,
                    detail=detail,
                    ip=ip,
                )
            )
            db.commit()
        except Exception:
            db.rollback()
        finally:
            db.close()

    @staticmethod
    def _parse_json(data: bytearray) -> dict | list | None:
        if not data:
            return None
        try:
            return json.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    @staticmethod
    def _build_summary(action: str, module: str, resource_id: int | None) -> str:
        if module == "notifications/read-all":
            return "全部通知标记为已读"
        module_name = MODULE_NAMES.get(module, module)
        if action == "delete" and resource_id is not None:
            return f"删除{module_name}记录（ID={resource_id}）"
        return f"{ACTION_NAMES.get(action, action)}{module_name}记录"
