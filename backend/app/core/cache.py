"""内存 TTL 缓存：用于首页/概览等高频聚合接口，避免短时间内重复计算。

特点：
- 进程内字典存储，进程重启自动清空。
- 支持按 key 设置 TTL（秒）。
- 线程安全（加锁）。
"""

import threading
import time
from typing import Any, Callable

_cache: dict[str, tuple[Any, float]] = {}
_lock = threading.Lock()


def get(key: str) -> Any | None:
    """获取缓存值，过期或不存在返回 None。"""
    with _lock:
        item = _cache.get(key)
        if item is None:
            return None
        value, expire_at = item
        if time.time() > expire_at:
            _cache.pop(key, None)
            return None
        return value


def set(key: str, value: Any, ttl: int = 30) -> None:
    """设置缓存值，ttl 单位为秒。"""
    with _lock:
        _cache[key] = (value, time.time() + ttl)


def invalidate(prefix: str | None = None) -> int:
    """清除指定前缀的缓存（或全部），返回清除条数。"""
    with _lock:
        if prefix is None:
            n = len(_cache)
            _cache.clear()
            return n
        keys = [k for k in _cache if k.startswith(prefix)]
        for k in keys:
            _cache.pop(k, None)
        return len(keys)


def cached(key_fn: Callable[..., str], ttl: int = 30) -> Callable:
    """装饰器：对函数结果做 TTL 缓存。key_fn 接收与原函数相同的参数，返回缓存键。"""

    def decorator(fn: Callable) -> Callable:
        def wrapper(*args, **kwargs):
            key = key_fn(*args, **kwargs)
            cached_val = get(key)
            if cached_val is not None:
                return cached_val
            result = fn(*args, **kwargs)
            set(key, result, ttl)
            return result

        return wrapper

    return decorator
