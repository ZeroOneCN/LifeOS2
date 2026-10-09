from functools import lru_cache
import warnings

from pydantic_settings import BaseSettings, SettingsConfigDict

# 默认（不安全）密钥，用于本地开发；生产环境必须修改
_DEFAULT_JWT_SECRET = "dev-only-insecure-secret-change-me-2f8d6c4b9a1e"


class Settings(BaseSettings):
    """应用配置，从环境变量 / .env 读取。"""

    PROJECT_NAME: str = "LifeOS API"
    API_V1_PREFIX: str = "/api/v1"
    CORS_ORIGINS: list[str] = [
        "http://localhost:9015",
        "http://127.0.0.1:9015",
    ]
    # 是否允许任意来源跨域（局域网/开发模式访问时启用；关闭后仅放行 CORS_ORIGINS 白名单）
    CORS_ALLOW_ALL: bool = True
    # 数据库连接串（必填，必须通过 .env 或环境变量提供，禁止在代码中硬编码账号密码）
    DATABASE_URL: str
    # 通知渠道敏感字段加密密钥（Fernet），为空时首次启动自动生成写入 .env
    NOTIFICATION_ENC_KEY: str = ""
    # 每日提醒扫描时间（HH:MM），默认每天 0:00 执行
    NOTIFY_SCAN_TIME: str = "00:00"
    # JWT 签名密钥（生产环境务必修改为随机值）
    JWT_SECRET_KEY: str = _DEFAULT_JWT_SECRET
    JWT_ALGORITHM: str = "HS256"
    # 访问令牌有效期（分钟），默认 24 小时
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 小时
    # 刷新令牌有效期（天），默认 7 天
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    # 登录失败锁定阈值（次）与锁定时长（分钟）
    LOGIN_MAX_FAILURES: int = 5
    LOGIN_LOCK_MINUTES: int = 15
    # 暴力破解检测：近 N 分钟内同一 IP 失败次数 ≥ 阈值则向管理员告警
    BRUTE_FORCE_WINDOW_MINUTES: int = 30
    BRUTE_FORCE_THRESHOLD: int = 10
    # mysqldump 可执行文件路径（留空则自动从 PATH 查找）
    MYSQLDUMP_PATH: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    # 启动校验：JWT 密钥仍为默认值时输出警告
    if s.JWT_SECRET_KEY == _DEFAULT_JWT_SECRET:
        warnings.warn(
            "JWT_SECRET_KEY 仍为默认不安全值！生产环境必须在 .env 中设置为随机长字符串。",
            stacklevel=2,
        )
    return s


settings = get_settings()
