"""日志统一配置、请求上下文（request id）与启动横幅。

- 级别由环境变量 ``LOG_LEVEL`` 控制（默认 INFO，非法值回退 INFO）。
- 终端格式精简为「时间 级别 logger [request id] 消息」，级别按等级着色；
  logger 名去掉 ``app.`` 前缀并对齐，未绑定 request id 时不占位。
- ``NO_COLOR`` 或非 TTY（重定向到文件、CI 捕获）自动降级为纯文本；
  Windows 下尝试开启 VT 处理，失败也自动降级，不引入额外依赖。
- uvicorn 的 ``uvicorn`` / ``uvicorn.error`` / ``uvicorn.access`` 复用同一
  handler 与 formatter，避免两套日志风格并存。
"""

import logging
import logging.config
import os
import re
import sys
import time
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Iterator, Sequence

# 请求上下文中的 request id；无请求上下文（启动、命令行任务）时为 "-"
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

_VALID_LEVELS = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}

# 外部传入的 X-Request-ID 仅允许字母、数字与 . _ -，长度 1~128，避免日志/响应头注入
_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")

# 日志级别配色：ERROR 红、WARNING 黄、INFO 青、DEBUG 灰、CRITICAL 加粗红
_LEVEL_COLORS = {
    "DEBUG": "90",
    "INFO": "36",
    "WARNING": "33",
    "ERROR": "31",
    "CRITICAL": "1;31",
}

_LEVEL_WIDTH = 7
_LOGGER_WIDTH = 24
_BANNER_WIDTH = 60

_configured = False
_ansi_enabled: bool | None = None


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


def _enable_windows_ansi() -> bool:
    """在 Windows 控制台开启 ANSI（VT）处理。

    kwargs:
        无。

    Returns:
        True 表示当前控制台支持 ANSI 转义；非 Windows 直接返回 True。
    """
    if os.name != "nt":
        return True
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        mode = ctypes.c_uint()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        flag = 0x0004  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        if mode.value & flag:
            return True
        return bool(kernel32.SetConsoleMode(handle, mode.value | flag))
    except Exception:  # noqa: BLE001 - 启用失败时仅降级为无色输出
        return False


def color_enabled() -> bool:
    """判断当前输出是否启用 ANSI 颜色（结果缓存）。

    kwargs:
        无。

    Returns:
        True 表示彩色输出；设置 ``NO_COLOR``、stdout 非 TTY 或 Windows 不支持 VT 时为 False。
    """
    global _ansi_enabled
    if _ansi_enabled is not None:
        return _ansi_enabled
    if os.getenv("NO_COLOR") is not None:
        _ansi_enabled = False
    elif not sys.stdout.isatty():
        _ansi_enabled = False
    else:
        _ansi_enabled = _enable_windows_ansi()
    return _ansi_enabled


def _paint(code: str, text: str, enabled: bool) -> str:
    """按 ANSI 码着色。

    Args:
        code: ANSI 颜色/样式码，如 ``36``。
        text: 待着色文本。
        enabled: 是否启用颜色。

    Returns:
        着色后的文本；未启用时原样返回。
    """
    return f"\x1b[{code}m{text}\x1b[0m" if enabled else text


def _shorten_logger_name(name: str) -> str:
    """简化 logger 名：去掉 ``app.`` 前缀，超宽时保留末尾层级。

    Args:
        name: 原始 logger 名。

    Returns:
        便于终端对齐展示的 logger 名（超宽时形如 ``…notification.scheduler``）。
    """
    short = name[4:] if name.startswith("app.") else name
    if len(short) <= _LOGGER_WIDTH:
        return short

    # 从最末一段开始向前拼接，尽量保留模块语义（末尾层级比开头更有辨识度）
    parts = short.split(".")
    tail = parts[-1]
    index = len(parts) - 1
    while index - 1 >= 0 and len(parts[index - 1]) + 1 + len(tail) <= _LOGGER_WIDTH - 1:
        index -= 1
        tail = f"{parts[index]}.{tail}"
    if len(tail) > _LOGGER_WIDTH - 1:
        tail = tail[-(_LOGGER_WIDTH - 1) :]
    return f"…{tail}"


class ConsoleFormatter(logging.Formatter):
    """终端日志格式化：紧凑、着色、对齐，异常堆栈保持纯文本完整输出。"""

    def __init__(self, use_color: bool) -> None:
        super().__init__()
        self.use_color = use_color

    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        """输出 HH:MM:SS 形式的时间。

        Args:
            record: 日志记录。
            datefmt: 未使用，保留基类签名。

        Returns:
            本地时间字符串。
        """
        return time.strftime("%H:%M:%S", time.localtime(record.created))

    def format(self, record: logging.LogRecord) -> str:
        """组装单条日志文本。

        Args:
            record: 日志记录。

        Returns:
            完整日志行（含异常堆栈）。
        """
        color = self.use_color
        ts = _paint("90", self.formatTime(record), color)
        level = record.levelname
        level_token = _paint(_LEVEL_COLORS.get(level, "37"), f"{level:<{_LEVEL_WIDTH}}", color)
        name_token = _paint("90", f"{_shorten_logger_name(record.name):<{_LOGGER_WIDTH}}", color)

        request_id = getattr(record, "request_id", "-")
        rid_token = ""
        if request_id and request_id != "-":
            rid_token = " " + _paint("35", f"[rid {request_id[:8]}]", color)

        message = record.getMessage()
        line = f"{ts} {level_token} {name_token}{rid_token} {message}"

        if record.exc_info:
            if not record.exc_text:
                record.exc_text = self.formatException(record.exc_info)
            line = f"{line}\n{record.exc_text}"
        if record.stack_info:
            line = f"{line}\n{self.formatStack(record.stack_info)}"
        return line


def create_console_formatter() -> ConsoleFormatter:
    """为 dictConfig 提供 formatter 工厂。

    kwargs:
        无。

    Returns:
        按当前终端能力决定是否着色的 ConsoleFormatter。
    """
    return ConsoleFormatter(use_color=color_enabled())


def _banner_lines(
    *,
    project_name: str,
    environment: str,
    host: str,
    port: int,
    api_prefix: str,
    database: str,
    jobs: Sequence[str],
) -> list[str]:
    """构造启动横幅文本行（不负责着色）。

    Args:
        project_name: 服务名。
        environment: 运行环境。
        host: 监听主机。
        port: 监听端口。
        api_prefix: API 前缀。
        database: 脱敏后的数据库目标。
        jobs: 定时任务概要列表。

    Returns:
        纯文本横幅行。
    """
    display_host = "127.0.0.1" if host in {"0.0.0.0", "::", ""} else host
    base = f"http://{display_host}:{port}"
    lines = [
        "=" * _BANNER_WIDTH,
        f"  {project_name}  ·  {environment}",
        "-" * _BANNER_WIDTH,
        f"  Local     {base}",
        f"  Docs      {base}/docs",
        f"  API       {base}{api_prefix}",
        f"  Database  {database}",
    ]
    if jobs:
        lines.append(f"  Jobs      {jobs[0]}")
        lines.extend(f"            {job}" for job in jobs[1:])
    lines.append("=" * _BANNER_WIDTH)
    return lines


def print_startup_banner(
    *,
    project_name: str,
    environment: str,
    host: str,
    port: int,
    api_prefix: str,
    database: str,
    jobs: Sequence[str],
) -> None:
    """打印后端启动横幅（自动按终端能力降级为无色）。

    参数均为关键字参数。

    Args:
        project_name: 服务名。
        environment: 运行环境。
        host: 监听主机。
        port: 监听端口。
        api_prefix: API 前缀。
        database: 已脱敏的数据库目标（禁止传入密码）。
        jobs: 定时任务概要列表。
    """
    color = color_enabled()
    lines = _banner_lines(
        project_name=project_name,
        environment=environment,
        host=host,
        port=port,
        api_prefix=api_prefix,
        database=database,
        jobs=jobs,
    )

    colored: list[str] = []
    for index, line in enumerate(lines):
        if index == 0 or index == len(lines) - 1:
            colored.append(_paint("90", line, color))
        elif index == 1:
            colored.append(_paint("1;36", line, color))
        elif index == 2:
            colored.append(_paint("90", line, color))
        elif line.startswith("  Local"):
            colored.append(_paint("90", "  Local     ", color) + _paint("4;36", line[12:], color))
        elif line.startswith("  Docs") or line.startswith("  API"):
            colored.append(_paint("90", line[:12], color) + _paint("36", line[12:], color))
        elif line.startswith("  Database"):
            colored.append(_paint("90", line[:12], color) + line[12:])
        elif line.startswith("  Jobs") or line.startswith("            "):
            colored.append(_paint("90", line[:12], color) + line[12:])
        else:
            colored.append(line)

    print("\n".join(colored), flush=True)


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
                # 工厂函数在配置时探测一次终端颜色能力
                "console": {"()": create_console_formatter},
            },
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "formatter": "console",
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
