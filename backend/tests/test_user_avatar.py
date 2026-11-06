"""头像上传与地址设置测试：鉴权、格式校验、大小限制、旧文件清理与静态访问。"""

import base64
import uuid

import pytest
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.testclient import TestClient

from app.api.routes import user as user_routes
from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.services.avatar_storage import detect_image_extension

# 1x1 透明 PNG
PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
    "YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)
# 仅用于魔数校验的伪 JPEG / WEBP（不参与解码）
JPEG_BYTES = b"\xff\xd8\xff" + b"0" * 16
WEBP_BYTES = b"RIFF\x00\x00\x00\x00WEBP" + b"0" * 16
AVATAR_PREFIX = f"{settings.API_V1_PREFIX}/uploads/avatars"


def _make_client(db, user: UserProfile, tmp_path, auth: bool = True) -> TestClient:
    """构造只挂载用户路由与头像静态目录的测试客户端。

    Args:
        db: 已绑定测试事务的数据库会话。
        user: 当前登录用户（用于覆盖鉴权依赖）。
        tmp_path: 头像落盘临时目录。
        auth: 是否覆盖鉴权依赖；False 时用于验证未登录返回 401。

    Returns:
        可直接调用头像接口的 TestClient。
    """
    app = FastAPI()
    app.include_router(user_routes.router, prefix=settings.API_V1_PREFIX)
    app.mount(
        AVATAR_PREFIX,
        StaticFiles(directory=str(tmp_path), check_dir=False),
        name="test-avatars",
    )

    def _override_db():
        """把路由的数据库依赖指向测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    if auth:
        app.dependency_overrides[get_current_user] = lambda: user
    return TestClient(app)


@pytest.fixture()
def avatar_user(db_session) -> UserProfile:
    """创建一个用于头像测试的用户记录（账号唯一，避免跨用例唯一约束冲突）。"""
    suffix = uuid.uuid4().hex[:12]
    profile = UserProfile(
        account=f"avatar_{suffix}",
        username=f"avatar_{suffix}",
        nickname="头像测试",
    )
    db_session.add(profile)
    db_session.commit()
    db_session.refresh(profile)
    return profile


@pytest.fixture()
def avatar_env(tmp_path, monkeypatch):
    """把头像目录指向 pytest 临时目录，避免污染真实 uploads。"""
    monkeypatch.setattr(settings, "AVATAR_UPLOAD_DIR", str(tmp_path))
    monkeypatch.setattr(settings, "AVATAR_MAX_BYTES", 2 * 1024 * 1024)
    return tmp_path


def _upload(client: TestClient, filename: str, content: bytes, mime: str = "image/png"):
    """以 multipart/form-data 方式上传头像文件。"""
    return client.post(
        f"{settings.API_V1_PREFIX}/user/avatar",
        files={"file": (filename, content, mime)},
    )


def test_upload_png_success_and_static_access(db_session, avatar_user, avatar_env):
    """上传 PNG 成功：返回相对地址、落盘随机文件名、静态 URL 可直接访问。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = _upload(client, "avatar.png", PNG_BYTES)

    assert resp.status_code == 200, resp.text
    avatar = resp.json()["avatar"]
    assert avatar.startswith(f"{AVATAR_PREFIX}/")
    assert avatar.endswith(".png")
    assert len(avatar.rsplit("/", 1)[-1].split(".")[0]) == 32  # uuid4 hex，不可猜测
    assert (avatar_env / avatar.rsplit("/", 1)[-1]).is_file()
    assert db_session.get(UserProfile, avatar_user.id).avatar == avatar

    static = client.get(avatar)
    assert static.status_code == 200
    assert static.headers["content-type"] == "image/png"


def test_upload_requires_login(db_session, avatar_user, avatar_env):
    """未登录上传必须返回 401，不允许写入任何用户头像。"""
    client = _make_client(db_session, avatar_user, avatar_env, auth=False)
    resp = _upload(client, "avatar.png", PNG_BYTES)
    assert resp.status_code == 401, resp.text
    assert list(avatar_env.glob("*.png")) == []


def test_upload_rejects_oversize(db_session, avatar_user, avatar_env):
    """超过 2 MB 上限返回 413，且不落盘。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = _upload(
        client,
        "big.png",
        PNG_BYTES + b"0" * (2 * 1024 * 1024 + 1),
    )
    assert resp.status_code == 413, resp.text
    assert "2 MB" in resp.json()["detail"]
    assert list(avatar_env.glob("*.png")) == []


def test_upload_rejects_unknown_extension(db_session, avatar_user, avatar_env):
    """扩展名不在白名单时返回 400，即使内容魔数是 PNG。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = _upload(client, "avatar.gif", PNG_BYTES)
    assert resp.status_code == 400, resp.text
    assert list(avatar_env.glob("*.png")) == []


def test_upload_rejects_non_image_content(db_session, avatar_user, avatar_env):
    """扩展名合法但内容不是图片时返回 400。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = _upload(client, "avatar.png", b"not an image at all")
    assert resp.status_code == 400, resp.text


def test_upload_supports_jpeg_and_webp(db_session, avatar_user, avatar_env):
    """JPEG / WEBP 魔数均可识别并落盘为对应扩展名。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    jpeg = _upload(client, "a.jpeg", JPEG_BYTES, "image/jpeg")
    webp = _upload(client, "a.webp", WEBP_BYTES, "image/webp")
    assert jpeg.status_code == 200, jpeg.text
    assert jpeg.json()["avatar"].endswith(".jpg")
    assert webp.status_code == 200, webp.text
    assert webp.json()["avatar"].endswith(".webp")


def test_replace_upload_deletes_previous_local_file(db_session, avatar_user, avatar_env):
    """再次上传时清理旧的本站头像文件，只保留最新一张。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    first = _upload(client, "first.png", PNG_BYTES).json()["avatar"]
    second = _upload(client, "second.png", PNG_BYTES).json()["avatar"]

    assert first != second
    assert not (avatar_env / first.rsplit("/", 1)[-1]).exists()
    assert (avatar_env / second.rsplit("/", 1)[-1]).is_file()
    assert list(avatar_env.glob("*.png")) == [avatar_env / second.rsplit("/", 1)[-1]]


@pytest.mark.parametrize("url", ["https://example.com/a.png", "http://cdn.example.com/a.png"])
def test_set_avatar_url_success(db_session, avatar_user, avatar_env, url):
    """http/https 外链可以设置，并原样返回。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = client.put(f"{settings.API_V1_PREFIX}/user/avatar", json={"avatar_url": url})
    assert resp.status_code == 200, resp.text
    assert resp.json()["avatar"] == url
    assert db_session.get(UserProfile, avatar_user.id).avatar == url


@pytest.mark.parametrize(
    "url",
    ["ftp://example.com/a.png", "javascript:alert(1)", "example.com/a.png", ""],
)
def test_set_avatar_url_rejects_invalid_scheme(db_session, avatar_user, avatar_env, url):
    """非 http/https、缺少主机名或空地址返回 400。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = client.put(f"{settings.API_V1_PREFIX}/user/avatar", json={"avatar_url": url})
    assert resp.status_code == 400, resp.text


def test_set_avatar_url_too_long(db_session, avatar_user, avatar_env):
    """地址超过头像列长度（255）时返回 400。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = client.put(
        f"{settings.API_V1_PREFIX}/user/avatar",
        json={"avatar_url": "https://example.com/" + "a" * 260 + ".png"},
    )
    assert resp.status_code == 400, resp.text


def test_set_url_deletes_previous_local_file(db_session, avatar_user, avatar_env):
    """从本站上传切换到外链时，旧文件被清理。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    uploaded = _upload(client, "avatar.png", PNG_BYTES).json()["avatar"]

    resp = client.put(
        f"{settings.API_V1_PREFIX}/user/avatar",
        json={"avatar_url": "https://example.com/next.png"},
    )
    assert resp.status_code == 200
    assert not (avatar_env / uploaded.rsplit("/", 1)[-1]).exists()


def test_clear_avatar_deletes_local_file(db_session, avatar_user, avatar_env):
    """avatar_url=null 清空头像，并清理本站旧文件。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    uploaded = _upload(client, "avatar.png", PNG_BYTES).json()["avatar"]

    resp = client.put(f"{settings.API_V1_PREFIX}/user/avatar", json={"avatar_url": None})
    assert resp.status_code == 200
    assert resp.json()["avatar"] is None
    assert db_session.get(UserProfile, avatar_user.id).avatar is None
    assert not (avatar_env / uploaded.rsplit("/", 1)[-1]).exists()


def test_static_avatar_not_found(db_session, avatar_user, avatar_env):
    """不存在的头像文件返回 404。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = client.get(f"{AVATAR_PREFIX}/{'0' * 32}.png")
    assert resp.status_code == 404


def test_profile_read_keeps_legacy_external_url(db_session, avatar_user, avatar_env):
    """兼容老数据：纯 URL 头像通过原有 profile 读取路径继续可用。"""
    avatar_user.avatar = "https://old.example.com/avatar.jpg"
    db_session.commit()

    client = _make_client(db_session, avatar_user, avatar_env)
    resp = client.get(f"{settings.API_V1_PREFIX}/user/profile")
    assert resp.status_code == 200
    assert resp.json()["avatar"] == "https://old.example.com/avatar.jpg"


def test_profile_update_still_accepts_avatar_and_cleans_old_file(
    db_session, avatar_user, avatar_env
):
    """旧资料更新接口仍可设置外链头像，并清理被替换的本站文件。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    uploaded = _upload(client, "avatar.png", PNG_BYTES).json()["avatar"]

    resp = client.put(
        f"{settings.API_V1_PREFIX}/user/profile",
        json={"avatar": "https://example.com/new.png"},
    )
    assert resp.status_code == 200, resp.text
    assert not (avatar_env / uploaded.rsplit("/", 1)[-1]).exists()


def test_profile_update_rejects_invalid_avatar_scheme(db_session, avatar_user, avatar_env):
    """资料更新中的头像字段同样只接受 http/https，非法 scheme 被 422 拦截。"""
    client = _make_client(db_session, avatar_user, avatar_env)
    resp = client.put(
        f"{settings.API_V1_PREFIX}/user/profile",
        json={"avatar": "javascript:alert(1)"},
    )
    assert resp.status_code == 422, resp.text


def test_detect_image_extension():
    """魔数识别：PNG / JPEG / WEBP 正确，其他内容返回 None。"""
    assert detect_image_extension(PNG_BYTES) == "png"
    assert detect_image_extension(JPEG_BYTES) == "jpg"
    assert detect_image_extension(WEBP_BYTES) == "webp"
    assert detect_image_extension(b"hello") is None
