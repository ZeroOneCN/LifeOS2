"""批量写接口防误删校验：缺失 / 空 ids 必须 422，且不得作用于任何记录。"""

from datetime import date
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel, ConfigDict

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import HealthSteps, LifestyleItem


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
        覆盖了数据库与当前用户的 TestClient。
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


def _make_items_client(db) -> TestClient:
    """构造挂载 lifestyle items 路由的测试客户端。

    Args:
        db: 已绑定测试会话的 Session 实例。

    Returns:
        覆盖了数据库与当前用户的 TestClient。
    """
    from app.api.routes.lifestyle.items import router as items_router

    app = FastAPI()
    app.include_router(items_router)

    def _override_db():
        """把路由的数据库依赖指到测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    return TestClient(app)


def _seed_steps(db) -> None:
    """插入两条步数记录用于验证「未被误删 / 误改」。"""
    db.add(HealthSteps(user_id=1, record_date=date(2026, 11, 1), period="am", steps=10))
    db.add(HealthSteps(user_id=1, record_date=date(2026, 11, 2), period="pm", steps=20))
    db.flush()


def test_batch_delete_rejects_missing_or_empty_ids(db_session):
    """批量删除缺 ids 或 ids 为空时返回 422，且一条记录都不能被删。"""
    _seed_steps(db_session)
    client = _make_steps_client(db_session)

    for body in ({}, {"ids": []}):
        resp = client.request("DELETE", "/steps/batch", json=body)
        assert resp.status_code == 422, (body, resp.text)

    assert db_session.query(HealthSteps).filter_by(user_id=1).count() == 2


def test_batch_patch_rejects_empty_ids(db_session):
    """批量更新 ids 为空时返回 422，已有数据不被修改。"""
    _seed_steps(db_session)
    client = _make_steps_client(db_session)

    resp = client.patch("/steps/batch", json={"ids": [], "fields": {"steps": 999}})

    assert resp.status_code == 422, resp.text
    assert db_session.query(HealthSteps).filter_by(user_id=1, steps=999).count() == 0


def test_items_batch_update_rejects_missing_or_empty_ids(db_session):
    """物品批量更新必须带非空 ids，否则 422 且原记录保持原状。"""
    item = LifestyleItem(
        user_id=1,
        item_name="测试物品",
        category="数码",
        status="in_use",
        purchase_date=date(2026, 11, 1),
        price=100,
        source="manual",
    )
    db_session.add(item)
    db_session.flush()
    client = _make_items_client(db_session)

    for body in (
        {"updates": {"status": "recycled"}},
        {"ids": [], "updates": {"status": "recycled"}},
    ):
        resp = client.put("/lifestyle/items/batch-update", json=body)
        assert resp.status_code == 422, (body, resp.text)

    db_session.refresh(item)
    assert item.status == "in_use"
