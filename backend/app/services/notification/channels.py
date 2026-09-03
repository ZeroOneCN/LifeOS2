"""通知渠道分发器：邮件/钉钉/飞书/企微/TGBot/Webhook 的统一发送入口。

全部基于 Python 标准库（smtplib + urllib），避免新增 HTTP 依赖。
"""

import json
import urllib.parse
import urllib.request
from email.mime.text import MIMEText
from email.utils import formataddr
from smtplib import SMTP, SMTP_SSL

from app.models.notification_center import NotificationChannel

from .crypto import decrypt_config

TIMEOUT = 10

TEST_TITLE = "通知中心测试"
TEST_CONTENT = "这是一条来自 LifeOS 通知中心的测试通知。如果你收到这条消息，说明渠道配置正确。"


# ---------- 底层 HTTP 辅助 ----------
def _post_json(
    url: str, payload: dict, headers: dict | None = None, timeout: int = TIMEOUT
) -> tuple[bool, str]:
    try:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            url, data=data, headers={"Content-Type": "application/json", **(headers or {})}
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
            return True, body[:500]
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def _post_form(url: str, fields: dict, timeout: int = TIMEOUT) -> tuple[bool, str]:
    try:
        data = urllib.parse.urlencode(fields).encode("utf-8")
        req = urllib.request.Request(url, data=data)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
            return True, body[:500]
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


# ---------- 各渠道发送函数 ----------
def send_email(config: dict, title: str, content: str, recipients: str | None) -> tuple[bool, str]:
    to_addrs = recipients or config.get("to_addr") or config.get("smtp_user") or ""
    to_list = [a.strip() for a in to_addrs.split(",") if a.strip()]
    if not to_list:
        return False, "未配置收件人"

    host = config.get("smtp_host")
    port = int(config.get("smtp_port", 465 if config.get("use_ssl") else 25))
    user = config.get("smtp_user")
    password = config.get("smtp_pass", "")
    from_name = config.get("from_name") or user
    from_addr = config.get("from_addr") or user
    msg = MIMEText(content, "plain", "utf-8")
    msg["Subject"] = title
    msg["From"] = formataddr((from_name or "", from_addr or ""))
    msg["To"] = ", ".join(to_list)
    try:
        if config.get("use_ssl"):
            server = SMTP_SSL(host, port, timeout=TIMEOUT)
        else:
            server = SMTP(host, port, timeout=TIMEOUT)
        server.login(user, password)
        server.sendmail(from_addr, to_list, msg.as_string())
        server.quit()
        return True, f"已发送到 {', '.join(to_list)}"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def send_webhook(config: dict, title: str, content: str, _recipients: str | None) -> tuple[bool, str]:
    url = config.get("url")
    if not url:
        return False, "未配置 URL"
    headers = None
    try:
        headers = json.loads(config.get("headers") or "{}")
    except Exception:
        headers = {}
    payload = {"title": title, "content": content}
    return _post_json(url, payload, headers)


def send_dingtalk(config: dict, title: str, content: str, _recipients: str | None) -> tuple[bool, str]:
    url = config.get("webhook_url")
    if not url:
        return False, "未配置 Webhook URL"
    payload = {"msgtype": "markdown", "markdown": {"title": title, "text": content}}
    return _post_json(url, payload)


def send_feishu(config: dict, title: str, content: str, _recipients: str | None) -> tuple[bool, str]:
    url = config.get("webhook_url")
    if not url:
        return False, "未配置 Webhook URL"
    payload = {"msg_type": "text", "content": {"text": f"{title}\n{content}"}}
    return _post_json(url, payload)


def send_workwechat(config: dict, title: str, content: str, _recipients: str | None) -> tuple[bool, str]:
    url = config.get("webhook_url")
    if not url:
        return False, "未配置 Webhook URL"
    payload = {"msgtype": "markdown", "markdown": {"content": f"**{title}**\n{content}"}}
    return _post_json(url, payload)


def send_tgbot(config: dict, title: str, content: str, _recipients: str | None) -> tuple[bool, str]:
    token = config.get("bot_token")
    chat_id = config.get("chat_id")
    if not token or not chat_id:
        return False, "未配置 Bot Token / Chat ID"
    text = f"{title}\n{content}"
    return _post_form(
        f"https://api.telegram.org/bot{token}/sendMessage",
        {"chat_id": chat_id, "text": text},
    )


CHANNEL_DISPATCHERS: dict[str, callable] = {
    "email": send_email,
    "dingtalk": send_dingtalk,
    "feishu": send_feishu,
    "workwechat": send_workwechat,
    "tgbot": send_tgbot,
    "webhook": send_webhook,
}

CHANNEL_LABELS: dict[str, str] = {
    "email": "邮件",
    "dingtalk": "钉钉",
    "feishu": "飞书",
    "workwechat": "企业微信",
    "tgbot": "Telegram Bot",
    "webhook": "Webhook",
}


def send_to_channel(channel: NotificationChannel, title: str, content: str) -> tuple[bool, str]:
    """向单个渠道发送通知；返回 (是否成功, 结果/错误信息)。"""
    if not channel.enabled:
        return False, f"渠道「{channel.name}」未启用"
    try:
        config = json.loads(channel.config or "{}")
    except Exception:
        config = {}
    config = decrypt_config(channel.channel_type, config)
    sender = CHANNEL_DISPATCHERS.get(channel.channel_type)
    if not sender:
        return False, f"不支持的渠道类型：{channel.channel_type}"
    ok, result = sender(config, title, content, channel.recipients)
    return ok, result


def test_channel(channel: NotificationChannel) -> tuple[bool, str]:
    """发送一条测试通知。"""
    return send_to_channel(channel, TEST_TITLE, TEST_CONTENT)