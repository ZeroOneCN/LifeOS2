# -*- coding: utf-8 -*-
"""配置管理：保存 Server 地址、账号、token 到本地 JSON 文件。

配置文件位于用户目录下的 .lifeos_loan_tool.json，避免与项目源码混在一起。
"""
import json
import os
from pathlib import Path

CONFIG_PATH = Path(os.path.expanduser("~")) / ".lifeos_loan_tool.json"

DEFAULT_SERVER = "http://localhost:8000"


def load_config() -> dict:
    """读取本地配置文件；不存在时返回默认配置。"""
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"server": DEFAULT_SERVER, "account": "", "token": ""}


def save_config(cfg: dict) -> None:
    """将配置写入本地 JSON 文件。"""
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
    except OSError:
        pass
