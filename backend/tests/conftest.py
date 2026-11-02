"""pytest 公共夹具：内存 SQLite 库 + 每用例独立事务回滚。

为什么选内存 SQLite（而不是独立 MySQL test schema）：
1. 本批用例覆盖的是纯函数与轻量 ORM 查询，不依赖 MySQL 专有语法；
   唯一需要的 MySQL 类型是 site_config 的 MEDIUMTEXT，这里为 SQLite 注册 TEXT 编译兜底。
2. 不依赖外部数据库服务，本机与 CI 都能直接跑，用例互相隔离且速度快。
3. 需要验证 MySQL 特有行为（如唯一约束的 NULL 语义、可重复读）时，再用
   `@pytest.mark.mysql` 标记的测试 schema 夹具补充，不与本夹具混用。
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.dialects.mysql import MEDIUMTEXT
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401  确保全部模型注册到 Base.metadata
from app.core.database import Base


@compiles(MEDIUMTEXT, "sqlite")
def _compile_mediumtext_sqlite(element, compiler, **kwargs) -> str:
    """把 MySQL 的 MEDIUMTEXT 在 SQLite 上降级为 TEXT，仅用于测试建表。"""
    return "TEXT"


@pytest.fixture(scope="session")
def engine():
    """会话级内存库引擎：整个测试会话共用一份表结构。"""
    eng = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=eng)
    yield eng
    Base.metadata.drop_all(bind=eng)
    eng.dispose()


@pytest.fixture()
def db_session(engine):
    """用例级会话：外层事务包住整个用例，结束回滚，保证用例互不污染。"""
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()
