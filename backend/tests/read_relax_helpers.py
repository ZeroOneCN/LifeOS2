"""响应模型放宽测试的共享辅助。

为什么单独放一个非 test_ 前缀的模块：health/finance/lifestyle/investment
四个域的放宽用例按域拆分在各自文件中，但构造 Read 基础字段、挂载通用 CRUD
路由的样板代码完全一致，抽到这里避免四份复制。
"""

from datetime import datetime
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user

ID = 1
TS = datetime(2026, 1, 1, 0, 0, 0)


def read_base() -> dict:
    """Read 模型共享的 ORM 审计字段。"""
    return {"id": ID, "created_at": TS, "updated_at": TS}


def make_client(db, *, prefix: str, model, create_schema, read_schema) -> TestClient:
    """构造只挂载单个通用 CRUD 路由的测试客户端。

    Args:
        db: 已绑定测试会话的 Session。
        prefix: 路由前缀。
        model: SQLAlchemy 模型类。
        create_schema: 请求侧 schema。
        read_schema: 响应侧 schema。

    Returns:
        覆盖了数据库与当前用户的 TestClient。
    """
    app = FastAPI()
    app.include_router(
        crud_router(
            prefix=prefix,
            tag=f"test-{prefix.strip('/')}",
            model=model,
            create_schema=create_schema,
            read_schema=read_schema,
            order_by=model.id,
        )
    )

    def _override_db():
        """把路由的数据库依赖指到测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=ID)
    return TestClient(app)
