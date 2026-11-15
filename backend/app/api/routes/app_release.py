"""移动端检查更新：版本清单读取接口。

清单（`android.json`）与 APK 由发布脚本生成
（`scripts/build_release_apk.ps1`），后端只做读取与字段校验，
APK 由静态目录 `/api/v1/downloads/` 托管，不经过 Python 进程传输。

接口匿名开放：登录页、未登录状态也要能检查更新，且清单不含任何用户数据。
"""

import json
import re
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from app.core.config import settings

router = APIRouter(prefix="/app/releases", tags=["app-release"])

# 清单文件名（与发布脚本约定，不要单独改名）
MANIFEST_NAME = "android.json"
# 语义版本：三段整数，禁止 1.0 / 1.0.0-beta 这类变体
_VERSION_NAME_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
_SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")


def release_dir() -> Path:
    """返回清单与 APK 的存放目录。

    配置值为绝对路径时原样使用，相对路径按 `backend/` 根目录解析，
    与 `AVATAR_UPLOAD_DIR` 的处理方式保持一致。

    Returns:
        发布目录 Path（不保证已存在）。
    """
    configured = Path(settings.APP_RELEASE_DIR)
    if configured.is_absolute():
        return configured
    # 本文件位于 backend/app/api/routes/，上溯三级即 backend/
    return Path(__file__).resolve().parents[3] / configured


def _invalid(field: str, message: str) -> HTTPException:
    """构造清单校验失败异常：错误码固定，便于客户端区分「清单坏了」与「连不上」。

    Args:
        field: 出错的字段名。
        message: 面向日志与排障的中文说明。

    Returns:
        状态码 500 的 HTTPException，响应体 `{detail: {code, field, message}}`。
    """
    return HTTPException(
        status_code=500,
        detail={"code": "manifest_invalid", "field": field, "message": message},
    )


def _require(manifest: dict[str, Any], field: str, expected: type) -> Any:
    """读取并校验必填字段的类型，缺失或类型不符时抛清单校验异常。

    Args:
        manifest: 已解析的清单字典。
        field: 字段名。
        expected: 期望的 Python 类型（int 会排除 bool，因为 bool 是 int 子类）。

    Returns:
        字段值。
    """
    value = manifest.get(field)
    if value is None:
        raise _invalid(field, f"清单缺少必填字段 {field}")
    if expected is int:
        # JSON 的 true/false 会被解析成 bool，这里必须挡掉，否则 version_code 会变成 1/0
        if isinstance(value, bool) or not isinstance(value, int):
            raise _invalid(field, f"{field} 必须是整数")
    elif not isinstance(value, expected):
        raise _invalid(field, f"{field} 类型应为 {expected.__name__}")
    return value


def read_manifest(path: Path) -> dict[str, Any]:
    """读取清单文件并逐字段校验。

    只做结构校验，不去核对 APK 是否存在、哈希是否匹配 —— 那些由发布脚本
    在写入前保证，运行期再校验一次会把 63 MB 文件的读取放进请求路径。

    Args:
        path: 清单文件路径。

    Returns:
        校验通过、可直接返回给客户端的清单字典。

    Raises:
        HTTPException: 文件不是合法 JSON（500）或字段不合法（500）。
    """
    try:
        # 用 utf-8-sig 读取：发布脚本在 Windows PowerShell 下容易写成带 BOM 的 UTF-8，
        # BOM 会让 json.loads 直接报错
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as error:
        raise _invalid("_file", f"清单文件无法解析：{error}") from error
    if not isinstance(raw, dict):
        raise _invalid("_file", "清单顶层必须是对象")

    manifest_version = _require(raw, "manifest_version", int)
    if manifest_version < 1:
        raise _invalid("manifest_version", "manifest_version 必须 ≥ 1")

    platform = _require(raw, "platform", str)
    if platform != "android":
        raise _invalid("platform", "platform 必须为 android")

    version_name = _require(raw, "version_name", str)
    if not _VERSION_NAME_PATTERN.match(version_name):
        raise _invalid("version_name", "version_name 必须是 major.minor.patch")

    version_code = _require(raw, "version_code", int)
    if version_code <= 0:
        raise _invalid("version_code", "version_code 必须为正整数")

    download_url = _require(raw, "download_url", str)
    if not download_url.strip():
        raise _invalid("download_url", "download_url 不能为空")

    sha256 = _require(raw, "sha256", str)
    if not _SHA256_PATTERN.match(sha256):
        raise _invalid("sha256", "sha256 必须是 64 位十六进制")

    size = _require(raw, "size", int)
    if size <= 0:
        raise _invalid("size", "size 必须为正整数")

    # 可选字段：类型不对时按缺失处理，不让整个清单因为展示项失败
    notes = raw.get("release_notes")
    published_at = raw.get("published_at")
    min_sdk = raw.get("min_android_sdk")
    cert = raw.get("signing_cert_sha256")

    return {
        "manifest_version": manifest_version,
        "platform": platform,
        "version_name": version_name,
        "version_code": version_code,
        "download_url": download_url.strip(),
        "sha256": sha256.lower(),
        "size": size,
        "release_notes": notes if isinstance(notes, str) else "",
        "published_at": published_at if isinstance(published_at, str) else "",
        "min_android_sdk": min_sdk if isinstance(min_sdk, int) and not isinstance(min_sdk, bool) else None,
        "signing_cert_sha256": cert if isinstance(cert, str) else "",
    }


@router.get("/android")
def android_release() -> JSONResponse:
    """返回 Android 最新版本清单。

    未发布过版本时返回 404 `release_not_found`；清单损坏返回 500
    `manifest_invalid`。两种错误必须区分，客户端才能给出不同提示。

    Returns:
        清单 JSON，`download_url` 若为相对路径且配置了 `PUBLIC_BASE_URL`
        则补成绝对地址；响应头 `Cache-Control: no-cache` 避免中间层缓存旧版本。
    """
    path = release_dir() / MANIFEST_NAME
    if not path.is_file():
        raise HTTPException(
            status_code=404,
            detail={
                "code": "release_not_found",
                "message": "服务器尚未发布 Android 版本清单",
            },
        )
    manifest = read_manifest(path)
    base = settings.PUBLIC_BASE_URL.strip().rstrip("/")
    if base and not manifest["download_url"].lower().startswith(("http://", "https://")):
        manifest["download_url"] = f"{base}/{manifest['download_url'].lstrip('/')}"
    return JSONResponse(content=manifest, headers={"Cache-Control": "no-cache"})
