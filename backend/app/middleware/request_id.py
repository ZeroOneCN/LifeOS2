"""request id 中间件：为每个请求绑定唯一标识并写回响应头。

实现要点：
- 优先复用调用方传入的 ``X-Request-ID``（做字符白名单校验，防注入），否则生成 uuid4。
- id 同时写入 ASGI ``scope`` 与 logging ``ContextVar``：前者供异常处理器在
  中间件退出后仍能取到，后者供日志过滤器使用。
- 位于活动日志中间件外层，保证活动日志的异常也能带上 request id。
"""

import uuid

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.logging_config import request_id_var, sanitize_request_id

REQUEST_ID_HEADER = b"x-request-id"


class RequestIdMiddleware:
    """纯 ASGI 中间件：生成/复用 request id 并写回响应头。"""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        """处理单个请求：绑定 request id、透传响应并补充响应头。

        Args:
            scope: ASGI 请求范围。
            receive: ASGI 接收通道。
            send: ASGI 发送通道。
        """
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = None
        for name, value in scope.get("headers", []):
            if name.lower() == REQUEST_ID_HEADER:
                incoming = value.decode("latin-1")
                break
        request_id = sanitize_request_id(incoming) or str(uuid.uuid4())

        scope["request_id"] = request_id
        token = request_id_var.set(request_id)

        async def send_wrapper(message: Message) -> None:
            """在响应开始时写入 X-Request-ID 响应头。"""
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["X-Request-ID"] = request_id
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            request_id_var.reset(token)
