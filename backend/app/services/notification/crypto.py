"""通知渠道敏感字段的 Fernet 加密/解密与脱敏工具。"""

from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet

from app.core.config import settings

# 各渠道类型中属于敏感字段的配置键（落库时加密，回显时脱敏）
SECRET_FIELDS: dict[str, list[str]] = {
    "email": ["smtp_pass"],
    "tgbot": ["bot_token"],
}

# backend 目录（crypto.py -> app/services/notification/crypto.py，往上 3 级）
_BACKEND_DIR = Path(__file__).resolve().parents[3]
_ENV_FILE = _BACKEND_DIR / ".env"

_fernet: Fernet | None = None


def _get_fernet() -> Fernet:
    """返回 Fernet 实例；密钥未配置时首次生成并持久化到 .env。"""
    global _fernet
    if _fernet is not None:
        return _fernet
    key = settings.NOTIFICATION_ENC_KEY
    if not key:
        key = Fernet.generate_key().decode()
        _append_env_key(key)
    _fernet = Fernet(key.encode())
    return _fernet


def _append_env_key(key: str) -> None:
    """把生成的密钥追加写入 backend/.env，保证重启后密钥一致。"""
    _ENV_FILE.parent.mkdir(parents=True, exist_ok=True)
    line = f"NOTIFICATION_ENC_KEY={key}"
    if _ENV_FILE.exists():
        content = _ENV_FILE.read_text(encoding="utf-8")
        if "NOTIFICATION_ENC_KEY=" in content:
            return
        with _ENV_FILE.open("a", encoding="utf-8") as f:
            f.write(("\n" if content and not content.endswith("\n") else "") + line + "\n")
    else:
        _ENV_FILE.write_text(line + "\n", encoding="utf-8")


def encrypt_value(value: str) -> str:
    """加密单个敏感值。"""
    return _get_fernet().encrypt(value.encode()).decode()


def decrypt_value(value: str) -> str:
    """解密单个敏感值；失败时原样返回。"""
    try:
        return _get_fernet().decrypt(value.encode()).decode()
    except Exception:
        return value


def is_secret(channel_type: str, key: str) -> bool:
    return key in SECRET_FIELDS.get(channel_type, [])


def encrypt_config(channel_type: str, config: dict[str, Any]) -> dict[str, Any]:
    """将 config 中的敏感字段加密，用于落库。"""
    for key in SECRET_FIELDS.get(channel_type, []):
        val = config.get(key)
        if val:
            config[key] = encrypt_value(str(val))
    return config


def decrypt_config(channel_type: str, config: dict[str, Any]) -> dict[str, Any]:
    """将 config 中的敏感字段解密，用于发送。"""
    for key in SECRET_FIELDS.get(channel_type, []):
        val = config.get(key)
        if val:
            config[key] = decrypt_value(str(val))
    return config


def mask_config(channel_type: str, config: dict[str, Any]) -> dict[str, Any]:
    """将 config 中的敏感字段脱敏，用于回显。值非空且非掩码时显示为 ******。"""
    for key in SECRET_FIELDS.get(channel_type, []):
        val = config.get(key)
        if val and val != "******":
            config[key] = "******"
    return config