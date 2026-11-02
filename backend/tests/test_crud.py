"""通用 CRUD 工具测试：日期回溯口径、批量 PATCH 字段白名单与唯一约束冲突映射。"""

from datetime import date, timedelta
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel, ConfigDict
from sqlalchemy.exc import IntegrityError

from app.api.crud import _allowed_patch_fields, _commit_or_conflict, crud_router, days_since
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import FinanceUtility, HealthSteps


def test_days_since_positive():
    """days>=1 表示含今天在内的近 N 天，起点为今天-(N-1)。"""
    assert days_since(30) == date.today() - timedelta(days=29)
    assert days_since(1) == date.today()


@pytest.mark.parametrize("days", [0, -1, -7])
def test_days_since_non_positive_returns_none(days):
    """days<=0 表示不过滤（返回 None），避免出现非法起始日。"""
    assert days_since(days) is None


def test_allowed_patch_fields_excludes_protected():
    """批量 PATCH 白名单必须排除主键、归属用户与审计时间戳。"""
    allowed = _allowed_patch_fields(FinanceUtility)
    assert {"id", "user_id", "created_at", "updated_at"}.isdisjoint(allowed)


def test_allowed_patch_fields_includes_business_columns():
    """业务字段仍应可批量修改，保证现有前端批量操作不受影响。"""
    allowed = _allowed_patch_fields(FinanceUtility)
    assert {"amount", "paid", "fee_type", "bill_month"}.issubset(allowed)


def test_allowed_patch_fields_health_steps():
    """白名单按模型列动态生成，对健康步数同样成立。"""
    allowed = _allowed_patch_fields(HealthSteps)
    assert "steps" in allowed
    assert "user_id" not in allowed
    assert "id" not in allowed


class _StepsCreate(BaseModel):
    """测试用步数创建请求体。"""

    record_date: date
    period: str = "full"
    steps: int


class _StepsRead(_StepsCreate):
    """测试用步数响应体。"""

    model_config = ConfigDict(from_attributes=True)
    id: int
    user_id: int


def _make_steps_client(db) -> TestClient:
    """构造只挂载 health_steps 通用 CRUD 路由的测试客户端。

    Args:
        db: 已绑定测试会话的 Session 实例。

    Returns:
        覆盖了数据库与当前用户的 TestClient，可直接调用 CRUD 端点。
    """

    app = FastAPI()
    app.include_router(
        crud_router(
            prefix="/steps",
            tag="test-steps",
            model=HealthSteps,
            create_schema=_StepsCreate,
            read_schema=_StepsRead,
            order_by=HealthSteps.record_date,
        )
    )

    def _override_db():
        """把路由的数据库依赖指到测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    return TestClient(app)


def test_create_duplicate_returns_409(db_session):
    """同一用户/日期/时段重复创建命中唯一约束时返回 409，而不是 500。"""
    client = _make_steps_client(db_session)
    payload = {"record_date": "2026-11-02", "period": "full", "steps": 1000}

    first = client.post("/steps", json=payload)
    assert first.status_code == 201, first.text

    second = client.post("/steps", json=payload)
    assert second.status_code == 409, second.text
    assert second.json()["detail"] == "已存在相同记录"


def test_commit_or_conflict_keeps_normal_commit(db_session):
    """无冲突时正常提交，成功路径行为不变。"""
    db_session.add(
        HealthSteps(user_id=2, record_date=date(2026, 11, 2), period="am", steps=10)
    )
    _commit_or_conflict(db_session)
    assert db_session.query(HealthSteps).filter_by(user_id=2).count() == 1


def test_commit_or_conflict_maps_integrity_error(db_session):
    """直接命中唯一约束时抛出 409，验证映射语义。"""
    key = {"user_id": 3, "record_date": date(2026, 11, 2), "period": "pm"}
    db_session.add(HealthSteps(**key, steps=1))
    db_session.commit()

    db_session.add(HealthSteps(**key, steps=2))
    with pytest.raises(Exception) as exc:
        _commit_or_conflict(db_session)
    assert getattr(exc.value, "status_code", None) == 409
    assert exc.value.detail == "已存在相同记录"
    assert isinstance(exc.value.__cause__, IntegrityError)
