from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """应用配置，从环境变量 / .env 读取。"""

    PROJECT_NAME: str = "LifeOS API"
    API_V1_PREFIX: str = "/api/v1"
    CORS_ORIGINS: list[str] = [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:5174",
        "http://127.0.0.1:5174",
    ]
    DATABASE_URL: str = (
        "mysql+pymysql://root:123456@127.0.0.1:3306/lifeos?charset=utf8mb4"
    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
