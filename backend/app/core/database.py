from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
)

SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


class Base(DeclarativeBase):
    """所有 ORM 模型的声明式基类。"""


def get_db():
    """FastAPI 依赖：提供数据库会话。"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
