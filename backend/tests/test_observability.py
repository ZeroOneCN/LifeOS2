"""可观测性测试：异常脱敏、request id 透传、健康检查最小化信息。"""

import logging

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import health_check
from app.core.errors import GENERIC_ERROR_MESSAGE, register_exception_handlers
from app.middleware.request_id import RequestIdMiddleware


def _make_app() -> FastAPI:
    """构造只包含 request id 中间件与全局异常处理器的测试应用。

    Returns:
        含正常路由与故意抛异常路由的 FastAPI 实例。
    """
    app = FastAPI()
    register_exception_handlers(app)
    app.add_middleware(RequestIdMiddleware)

    @app.get("/ok")
    def ok() -> dict[str, bool]:
        return {"ok": True}

    @app.get("/boom")
    def boom() -> dict[str, bool]:
        raise RuntimeError("secret internal detail: lifeos.internal_table")
    return app


def test_unhandled_exception_does_not_leak_internal_info(caplog):
    """未捕获异常返回结构化 JSON，含 request id，且不回显异常原文/表名/堆栈。"""
    client = TestClient(_make_app(), raise_server_exceptions=False)
    with caplog.at_level(logging.ERROR, logger="app.errors"):
        resp = client.get("/boom")

    assert resp.status_code == 500
    body = resp.json()
    assert body["detail"] == GENERIC_ERROR_MESSAGE
    assert body["request_id"]
    assert resp.headers["X-Request-ID"] == body["request_id"]

    # 客户端响应体不得出现任何内部异常字符串
    assert "secret internal detail" not in resp.text
    assert "lifeos.internal_table" not in resp.text
    assert "Traceback" not in resp.text

    # 服务端日志必须保留完整异常信息（exc_info）
    assert any(record.exc_info for record in caplog.records)


def test_request_id_reused_from_header():
    """合法 X-Request-ID 复用并写回响应头。"""
    client = TestClient(_make_app())
    resp = client.get("/ok", headers={"X-Request-ID": "trace-abc.123"})
    assert resp.status_code == 200
    assert resp.headers["X-Request-ID"] == "trace-abc.123"


@pytest.mark.parametrize("bad_id", ["bad id with space", "x" * 129, "id\ninjected"])
def test_invalid_request_id_is_regenerated(bad_id):
    """非法 X-Request-ID（空格、超长、换行注入）不会被复用。"""
    client = TestClient(_make_app())
    resp = client.get("/ok", headers={"X-Request-ID": bad_id})
    assert resp.status_code == 200
    new_id = resp.headers["X-Request-ID"]
    assert new_id != bad_id
    assert len(new_id) == 36  # uuid4 字符串长度


def test_health_hides_internal_error_and_includes_report_scheduler(monkeypatch):
    """健康检查只返回最小状态，不包含数据库异常原文，且纳入月报调度器。"""
    class _FailingEngine:
        """模拟数据库连接失败的引擎。"""

        def connect(self):
            raise RuntimeError("Access denied: lifeos.patient_table")

    monkeypatch.setattr(health_check, "engine", _FailingEngine())
    monkeypatch.setattr(health_check.notification_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check.backup_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check.report_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check, "get_job_states", lambda: {})

    data = health_check.health_check()

    assert data["status"] == "degraded"
    assert data["database"] == {"status": "error"}
    assert set(data["schedulers"]) == {"notification", "backup", "report"}
    assert data["schedulers"]["report"] == "running"
    # 不得回显异常原文、磁盘用量等内部细节
    assert "Access denied" not in str(data)
    assert "patient_table" not in str(data)
    assert "disk" not in data


def test_health_ok_when_database_and_schedulers_up(monkeypatch):
    """数据库与三个调度器均正常时整体状态为 ok，数据库条目不含 detail 字段。"""
    monkeypatch.setattr(health_check, "_check_database", lambda: True)
    monkeypatch.setattr(health_check.notification_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check.backup_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check.report_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check, "get_job_states", lambda: {})

    data = health_check.health_check()

    assert data["status"] == "ok"
    assert data["database"] == {"status": "ok"}


def test_health_exposes_job_status_without_error_text(monkeypatch):
    """健康检查展示各 job 最近执行结果，但不暴露错误摘要原文。"""
    states = {
        "backup_scheduled_scan": {
            "status": "failed",
            "started_at": "2026-11-04T03:00:00",
            "finished_at": "2026-11-04T03:00:01",
            "duration_ms": 1000,
        }
    }
    monkeypatch.setattr(health_check, "_check_database", lambda: True)
    monkeypatch.setattr(health_check.notification_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check.backup_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check.report_scheduler, "is_running", lambda: True)
    monkeypatch.setattr(health_check, "get_job_states", lambda: states)

    data = health_check.health_check()

    assert data["jobs"]["backup_scheduled_scan"]["status"] == "failed"
    assert "error_summary" not in data["jobs"]["backup_scheduled_scan"]
    assert "detail" not in str(data)
