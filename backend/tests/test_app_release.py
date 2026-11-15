"""检查更新接口测试：清单读取、字段校验、错误码与静态目录。

清单由发布脚本生成，这里用临时目录构造，不依赖真实 APK。
"""

import json
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import app_release
from app.core.config import settings

VALID = {
    "manifest_version": 1,
    "platform": "android",
    "version_name": "1.0.0",
    "version_code": 2008,
    "download_url": "/api/v1/downloads/LifeOS-1.0.0-2008.apk",
    "sha256": "a" * 64,
    "size": 63239430,
    "release_notes": "修复若干问题",
    "published_at": "2026-11-15T16:20:00+08:00",
    "min_android_sdk": 26,
    "signing_cert_sha256": "b" * 64,
}


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    """构造只挂载发布路由的测试客户端，并把发布目录指向临时目录。

    Args:
        tmp_path: pytest 临时目录。
        monkeypatch: 用于覆盖配置项。

    Returns:
        可直接请求 /app/releases/android 的 TestClient。
    """
    monkeypatch.setattr(settings, "APP_RELEASE_DIR", str(tmp_path))
    monkeypatch.setattr(settings, "PUBLIC_BASE_URL", "")
    app = FastAPI()
    app.include_router(app_release.router, prefix=settings.API_V1_PREFIX)
    return TestClient(app)


def _write(tmp_path: Path, payload: dict) -> None:
    """把清单写入临时发布目录。"""
    (tmp_path / app_release.MANIFEST_NAME).write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8"
    )


def test_manifest_not_found(client: TestClient) -> None:
    """未发布过版本时返回 404 与固定错误码，便于客户端区分。"""
    response = client.get(f"{settings.API_V1_PREFIX}/app/releases/android")
    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "release_not_found"


def test_manifest_ok(client: TestClient, tmp_path: Path) -> None:
    """合法清单原样返回，且带 no-cache 与相对下载地址。"""
    _write(tmp_path, VALID)
    response = client.get(f"{settings.API_V1_PREFIX}/app/releases/android")
    assert response.status_code == 200
    body = response.json()
    assert body["version_code"] == 2008
    assert body["sha256"] == "a" * 64
    assert body["download_url"] == VALID["download_url"]
    assert response.headers["cache-control"] == "no-cache"


def test_manifest_download_url_absolutized(
    client: TestClient, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """配置了 PUBLIC_BASE_URL 时相对地址补成绝对地址；绝对地址不被二次拼接。"""
    _write(tmp_path, VALID)
    monkeypatch.setattr(settings, "PUBLIC_BASE_URL", "http://192.168.8.103:9515/")
    body = client.get(f"{settings.API_V1_PREFIX}/app/releases/android").json()
    assert body["download_url"] == (
        "http://192.168.8.103:9515/api/v1/downloads/LifeOS-1.0.0-2008.apk"
    )

    absolute = dict(VALID, download_url="https://cdn.example.com/a.apk")
    _write(tmp_path, absolute)
    body = client.get(f"{settings.API_V1_PREFIX}/app/releases/android").json()
    assert body["download_url"] == "https://cdn.example.com/a.apk"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("version_name", "1.0"),
        ("version_code", "2008"),
        ("version_code", True),
        ("sha256", "abc"),
        ("size", 0),
        ("platform", "ios"),
        ("manifest_version", 0),
    ],
)
def test_manifest_invalid_fields(
    client: TestClient, tmp_path: Path, field: str, value: object
) -> None:
    """字段非法时返回 500 manifest_invalid 并指出字段名。"""
    _write(tmp_path, dict(VALID, **{field: value}))
    response = client.get(f"{settings.API_V1_PREFIX}/app/releases/android")
    assert response.status_code == 500
    detail = response.json()["detail"]
    assert detail["code"] == "manifest_invalid"
    assert detail["field"] == field


def test_manifest_missing_field(client: TestClient, tmp_path: Path) -> None:
    """缺少必填字段同样归为清单非法。"""
    payload = dict(VALID)
    payload.pop("sha256")
    _write(tmp_path, payload)
    response = client.get(f"{settings.API_V1_PREFIX}/app/releases/android")
    assert response.status_code == 500
    assert response.json()["detail"]["field"] == "sha256"


def test_manifest_broken_json(client: TestClient, tmp_path: Path) -> None:
    """清单不是合法 JSON 时返回清单非法，而不是 500 堆栈。"""
    (tmp_path / app_release.MANIFEST_NAME).write_text("{not json", encoding="utf-8")
    response = client.get(f"{settings.API_V1_PREFIX}/app/releases/android")
    assert response.status_code == 500
    assert response.json()["detail"]["code"] == "manifest_invalid"


def test_release_dir_relative_to_backend() -> None:
    """相对目录按 backend 根目录解析，绝对目录原样返回。"""
    original = settings.APP_RELEASE_DIR
    try:
        settings.APP_RELEASE_DIR = "downloads"
        assert app_release.release_dir().name == "downloads"
        settings.APP_RELEASE_DIR = str(Path.cwd())
        assert app_release.release_dir() == Path.cwd()
    finally:
        settings.APP_RELEASE_DIR = original
