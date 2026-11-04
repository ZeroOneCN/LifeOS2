"""全局异常处理：未捕获异常统一返回结构化 JSON，且不泄露内部细节。

内部异常字符串、堆栈、SQL/表名只写入服务端日志；客户端仅拿到通用错误文案
与 request id，便于按 id 在日志中定位。
"""

import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.core.logging_config import bind_request_id

logger = logging.getLogger("app.errors")

# 对外统一文案，避免暴露异常原文、表名或堆栈
GENERIC_ERROR_MESSAGE = "服务器内部错误，请稍后重试"


def _current_request_id(request: Request) -> str:
    """从 ASGI scope 读取 request id（异常处理器在中间件退出后执行，无法读 ContextVar）。

    Args:
        request: 当前请求对象。

    Returns:
        request id；缺失时返回 "-"。
    """
    return str(request.scope.get("request_id") or "-")


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """处理未捕获异常：记录完整异常，返回脱敏后的结构化响应。

    Args:
        request: 当前请求。
        exc: 未捕获的异常实例（由日志的 exc_info 记录完整堆栈）。

    Returns:
        包含 ``detail`` 与 ``request_id`` 的 500 JSON 响应，并回写 X-Request-ID 响应头。
    """
    request_id = _current_request_id(request)
    # 临时绑定 context，确保异常日志也带上 request id
    with bind_request_id(request_id):
        logger.exception("未处理异常：%s %s", request.method, request.url.path)

    return JSONResponse(
        status_code=500,
        content={"detail": GENERIC_ERROR_MESSAGE, "request_id": request_id},
        headers={"X-Request-ID": request_id},
    )


def register_exception_handlers(app: FastAPI) -> None:
    """注册全局异常处理器。

    Args:
        app: FastAPI 应用实例。

    Returns:
        无返回值。
    """
    app.add_exception_handler(Exception, unhandled_exception_handler)
