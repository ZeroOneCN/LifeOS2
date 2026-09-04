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
    # 是否允许任意来源跨域（局域网/开发模式访问时启用；关闭后仅放行 CORS_ORIGINS 白名单）
    CORS_ALLOW_ALL: bool = True
    DATABASE_URL: str = (
        "mysql+pymysql://root:123456@127.0.0.1:3306/lifeos?charset=utf8mb4"
    )
    # 通知渠道敏感字段加密密钥（Fernet），为空时首次启动自动生成写入 .env
    NOTIFICATION_ENC_KEY: str = ""
    # 每日提醒扫描时间（HH:MM），默认每天 0:00 执行
    NOTIFY_SCAN_TIME: str = "00:00"
    # JWT 签名密钥（生产环境务必修改为随机值）
    JWT_SECRET_KEY: str = "dev-only-insecure-secret-change-me-2f8d6c4b9a1e"
    JWT_ALGORITHM: str = "HS256"
    # 访问令牌有效期（分钟），默认 7 天
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
