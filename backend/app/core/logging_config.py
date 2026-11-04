"""日志统一配置与请求上下文（request id）。

- 级别由环境变量 ``LOG_LEVEL`` 控制（默认 INFO，非法值回退 INFO）。
- 输出格式固定包含时间、级别、logger 名与 request id，便于与访问日志对齐排查。
- request id 通过 ``ContextVar`` 在同一请求协程/线程内传递，日志过滤器读取后注入。
"""

import logging
import logging.config
import os
import re
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Iterator

# 请求上下文中的 request id；无请求上下文（启动、命令行任务）时为 "-"
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

# 日志格式：时间 级别 [logger] [request_id=...] 消息
LOG_FORMAT = (
    "%(asctime)s %(levelname)s [%(name)s] [request_id=%(request_id)s] %(message)s"
)

_VALID_LEVELS = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}

# 外部传入的 X-Request-ID 仅允许字母、数字与 . _ -，长度 1~128，避免日志/响应头注入
_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")

_configured = False


class RequestIdFilter(logging.Filter):
    """把当前请求的 request id 注入每条日志记录。"""

    def filter(self, record: logging.LogRecord) -> bool:
        """为日志记录补充 request_id 字段，始终返回 True 不丢弃日志。

        Args:
            record: 待输出的日志记录。

        Returns:
            固定返回 True，保证日志正常输出。
        """
        record.request_id = request_id_var.get()
        return True


def sanitize_request_id(value: str | None) -> str | None:
    """校验并规范化外部传入的 request id。

    Args:
        value: 请求头 ``X-Request-ID`` 的原始值。

    Returns:
        合法时返回去空白后的 id；为空或含非法字符时返回 None（由调用方生成新 id）。
    """
    if not value:
        return None
    candidate = value.strip()
    return candidate if _REQUEST_ID_PATTERN.match(candidate) else None


@contextmanager
def bind_request_id(request_id: str) -> Iterator[None]:
    """在指定代码块内绑定 request id，退出时恢复原值。

    Args:
        request_id: 需要在日志中呈现的 request id。
    """
    token = request_id_var.set(request_id)
    try:
        yield
    finally:
        request_id_var.reset(token)


def setup_logging() -> None:
    """初始化全局日志配置（幂等）。

    kwargs:
        无。

    Returns:
        无返回值；重复调用不会重复添加 handler。
    """
    global _configured
    if _configured:
        return

    level = os.getenv("LOG_LEVEL", "INFO").strip().upper()
    if level not in _VALID_LEVELS:
        level = "INFO"

    logging.config.dictConfig(
        {
            "version": 1,
            # 保留已有 logger（uvicorn 在导入应用前已创建），仅调整级别与 handler
            "disable_existing_loggers": False,
            "filters": {
                "request_id": {"()": RequestIdFilter},
            },
            "formatters": {
                "default": {
                    "format": LOG_FORMAT,
                    "datefmt": "%Y-%m-%d %H:%M:%S",
                },
            },
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "formatter": "default",
                    "filters": ["request_id"],
                    "stream": "ext://sys.stdout",
                },
            },
            "root": {"level": level, "handlers": ["console"]},
            "loggers": {
                "uvicorn": {"level": level, "handlers": ["console"], "propagate": False},
                "uvicorn.error": {
                    "level": level,
                    "handlers": ["console"],
                    "propagate": False,
                },
                "uvicorn.access": {
                    "level": level,
                    "handlers": ["console"],
                    "propagate": False,
                },
            },
        }
    )
    _configured = True
