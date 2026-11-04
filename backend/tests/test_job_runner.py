"""定时任务统一抢占与执行状态落库测试。"""

from contextlib import contextmanager

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ScheduledJobState
from app.services import job_runner


def _fake_lock(acquired: bool):
    """构造模拟的命名锁上下文：固定返回是否抢到锁。

    Args:
        acquired: True 表示抢到锁，False 表示其他实例正在执行。

    Returns:
        可直接替换 ``job_runner.job_lock`` 的上下文管理器工厂。
    """

    @contextmanager
    def _cm(_job_name: str):
        yield acquired

    return _cm


def _session_factory(db_session):
    """基于测试连接创建独立会话，提交以 savepoint 形式落在用例事务内。

    Args:
        db_session: 用例级会话，提供底层连接。

    Returns:
        无参会话工厂。
    """
    connection = db_session.get_bind()
    return lambda: Session(bind=connection, join_transaction_mode="create_savepoint")


def _state(db_session, job_name: str) -> ScheduledJobState | None:
    """读取指定任务的最近执行状态。

    Args:
        db_session: 测试会话。
        job_name: 任务名。

    Returns:
        状态行或 None。
    """
    return db_session.scalar(
        select(ScheduledJobState).where(ScheduledJobState.job_name == job_name)
    )


def test_run_job_success_records_state(db_session, monkeypatch):
    """抢到锁时执行任务并落库 success、耗时与起止时间。"""
    called: list[int] = []
    monkeypatch.setattr(job_runner, "job_lock", _fake_lock(True))

    def task(db: Session) -> None:
        called.append(1)

    status = job_runner.run_job(
        "unit_test_success", task, session_factory=_session_factory(db_session)
    )

    assert status == "success"
    assert called == [1]
    row = _state(db_session, "unit_test_success")
    assert row is not None
    assert row.status == "success"
    assert row.started_at is not None
    assert row.finished_at is not None
    assert row.duration_ms is not None and row.duration_ms >= 0
    assert row.error_summary is None


def test_run_job_skips_when_lock_not_acquired(db_session, monkeypatch):
    """未抢到锁时跳过本轮：任务体不执行，状态记录 skipped。"""
    called: list[int] = []
    monkeypatch.setattr(job_runner, "job_lock", _fake_lock(False))

    def task(db: Session) -> None:
        called.append(1)

    status = job_runner.run_job(
        "unit_test_skip", task, session_factory=_session_factory(db_session)
    )

    assert status == "skipped"
    assert called == []
    row = _state(db_session, "unit_test_skip")
    assert row is not None
    assert row.status == "skipped"
    assert row.duration_ms == 0


def test_run_job_failure_records_truncated_error(db_session, monkeypatch):
    """任务异常不向外抛出，状态记录 failed，错误摘要截断且不越界。"""
    monkeypatch.setattr(job_runner, "job_lock", _fake_lock(True))

    def task(db: Session) -> None:
        raise RuntimeError("boom-" + "x" * 500)

    status = job_runner.run_job(
        "unit_test_failure", task, session_factory=_session_factory(db_session)
    )

    assert status == "failed"
    row = _state(db_session, "unit_test_failure")
    assert row is not None
    assert row.status == "failed"
    assert row.error_summary is not None
    assert row.error_summary.startswith("boom-")
    assert len(row.error_summary) == job_runner.ERROR_SUMMARY_MAX
