# -*- coding: utf-8 -*-
"""活动日志写入助手：统一承载人工操作之外的后台自动化任务留痕。"""
from __future__ import annotations

import json

from sqlalchemy.orm import Session

from app.models import ActivityLog

# 自动化任务统一操作类型：前端会渲染为「自动」并支持筛选
AUTO_ACTION = "auto"
# 自动化任务默认来源标记，写入 user_agent 便于区分人工操作
AUTO_USER_AGENT = "system-auto"
MAX_DETAIL = 2000


def log_activity(
    db: Session,
    *,
    user_id: int,
    action: str,
    module: str,
    summary: str,
    resource_type: str | None = None,
    resource_id: int | None = None,
    detail: str | dict | list | None = None,
    ip: str | None = None,
    user_agent: str = AUTO_USER_AGENT,
) -> ActivityLog:
    """写入一条活动日志（不提交事务，由调用方统一提交）。

    Args:
        db: 数据库会话。
        user_id: 归属用户 ID。
        action: 操作类型（create/update/patch/delete/auto）。
        module: 模块路径，如 health/reports。
        summary: 中文操作摘要。
        resource_type: 资源类型，默认取模块路径末段。
        resource_id: 资源 ID。
        detail: 操作详情，字典/列表会自动 JSON 序列化。
        ip: 来源 IP。
        user_agent: 客户端标识，自动化任务默认 system-auto。

    Returns:
        已加入会话、尚未提交的 ActivityLog 实例。
    """
    if isinstance(detail, (dict, list)):
        detail = json.dumps(detail, ensure_ascii=False)
    if detail and len(detail) > MAX_DETAIL:
        detail = detail[:MAX_DETAIL] + "…"
    entry = ActivityLog(
        user_id=user_id,
        action=action,
        module=module,
        resource_type=resource_type or module.split("/")[-1] or module,
        resource_id=resource_id,
        summary=summary,
        detail=detail,
        ip=ip,
        user_agent=user_agent,
    )
    db.add(entry)
    return entry
