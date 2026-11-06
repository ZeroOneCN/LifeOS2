"""头像存储：图片格式校验、落盘、旧文件清理与访问地址生成。

落盘约定：
1. 文件名使用 uuid4 十六进制（32 位，不可猜测），扩展名由文件内容魔数推断；
2. 数据库只保存 `/api/v1/uploads/avatars/<文件名>` 形式的相对地址；
3. 外链头像原样保存，读取时无需区分来源；
4. 静态资源挂载在 API 前缀下，保证生产 Nginx 只反代 `/api/` 时仍可访问。
"""

from pathlib import Path
import re
import uuid
from urllib.parse import urlparse

from app.core.config import settings

# 允许的图片格式（按文件内容魔数识别，避免仅凭扩展名误判）
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_JPEG_SIGNATURE = b"\xff\xd8\xff"
_ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
# 本站头像文件名：32 位十六进制 + 允许的扩展名（用于判断是否需要删旧文件）
_LOCAL_NAME_RE = re.compile(r"^[0-9a-f]{32}\.(?:png|jpg|jpeg|webp)$")
# 与 UserProfile.avatar 列长度（String(255)）保持一致
_MAX_URL_LEN = 255


def avatar_upload_dir() -> Path:
    """返回头像落盘目录（相对配置自动拼接到 backend 根目录）。

    Returns:
        头像目录的绝对路径（目录可能尚不存在）。
    """
    configured = Path(settings.AVATAR_UPLOAD_DIR)
    if configured.is_absolute():
        return configured
    backend_root = Path(__file__).resolve().parents[2]
    return backend_root / configured


def avatar_url_prefix() -> str:
    """返回本站头像的访问路径前缀（与 API 前缀一致）。"""
    return f"{settings.API_V1_PREFIX}/uploads/avatars"


def ensure_avatar_dir() -> Path:
    """创建头像目录（已存在时直接返回）。

    Returns:
        头像目录路径。
    """
    path = avatar_upload_dir()
    path.mkdir(parents=True, exist_ok=True)
    return path


def detect_image_extension(content: bytes) -> str | None:
    """根据文件魔数判断图片类型。

    Args:
        content: 文件内容（至少前 12 字节）。

    Returns:
        ``png`` / ``jpg`` / ``webp``；无法识别时返回 None。
    """
    if content.startswith(_PNG_SIGNATURE):
        return "png"
    if content.startswith(_JPEG_SIGNATURE):
        return "jpg"
    if len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        return "webp"
    return None


def validate_image_upload(filename: str | None, content: bytes) -> str:
    """校验上传文件并返回落盘扩展名。

    Args:
        filename: 客户端原始文件名（仅用于取扩展名）。
        content: 已读取的文件内容。

    Returns:
        推断出的扩展名（png/jpg/webp）。

    Raises:
        ValueError: 扩展名不在白名单，或文件内容不是允许的图片格式。
    """
    suffix = Path(filename or "").suffix.lower()
    if suffix not in _ALLOWED_EXTENSIONS:
        raise ValueError("仅支持 PNG、JPG、JPEG、WEBP 格式的图片")
    ext = detect_image_extension(content)
    if ext is None:
        raise ValueError("文件内容不是有效的图片，请重新选择")
    return ext


def save_avatar_file(content: bytes, ext: str) -> str:
    """把头像写入落盘目录并返回数据库应保存的相对地址。

    Args:
        content: 图片二进制内容。
        ext: ``validate_image_upload`` 返回的扩展名。

    Returns:
        形如 ``/api/v1/uploads/avatars/<32位hex>.png`` 的相对地址。
    """
    directory = ensure_avatar_dir()
    name = f"{uuid.uuid4().hex}.{ext}"
    (directory / name).write_bytes(content)
    return f"{avatar_url_prefix()}/{name}"


def is_local_avatar(value: str | None) -> bool:
    """判断头像地址是否指向本站上传的文件。

    Args:
        value: 数据库中的头像字段值。

    Returns:
        True 表示本站上传文件；外链、空值或非法文件名均返回 False。
    """
    if not value:
        return False
    prefix = f"{avatar_url_prefix()}/"
    if not value.startswith(prefix):
        return False
    return bool(_LOCAL_NAME_RE.match(value[len(prefix):]))


def delete_local_avatar(value: str | None) -> None:
    """删除本站上传的头像文件；外链或空值跳过，文件已不存在也不报错。

    Args:
        value: 被替换下来的旧头像地址。
    """
    if not is_local_avatar(value):
        return
    name = value.rsplit("/", 1)[-1]
    try:
        (avatar_upload_dir() / name).unlink(missing_ok=True)
    except OSError:
        # 清理失败不影响主流程，仅留待人工排查
        pass


def validate_avatar_url(value: str) -> str:
    """校验外链头像地址。

    Args:
        value: 用户输入的图片地址。

    Returns:
        去除首尾空白后的地址。

    Raises:
        ValueError: 为空、超长，或 scheme 不是 http/https、缺少主机名。
    """
    url = value.strip()
    if not url:
        raise ValueError("头像地址不能为空")
    if len(url) > _MAX_URL_LEN:
        raise ValueError(f"头像地址过长（最多 {_MAX_URL_LEN} 个字符）")
    parsed = urlparse(url)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.netloc:
        raise ValueError("头像地址必须是 http:// 或 https:// 开头的图片链接")
    return url
