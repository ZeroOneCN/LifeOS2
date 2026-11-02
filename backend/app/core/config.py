from functools import lru_cache
import warnings

from pydantic_settings import BaseSettings, SettingsConfigDict

# 默认（不安全）密钥，用于本地开发；生产环境必须修改
_DEFAULT_JWT_SECRET = "dev-only-insecure-secret-change-me-2f8d6c4b9a1e"
# 视为本地开发的环境名，其余取值均按生产环境校验密钥
_DEV_ENVIRONMENTS = {"development", "dev", "local", "test"}


class Settings(BaseSettings):
    """应用配置，从环境变量 / .env 读取。"""

    PROJECT_NAME: str = "LifeOS API"
    API_V1_PREFIX: str = "/api/v1"
    # 运行环境：development（默认，本地开发）/ production（生产）
    ENVIRONMENT: str = "development"
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
    # 每月 1 日自动生成上月报告的时间（HH:MM），默认 00:10
    MONTHLY_REPORT_TIME: str = "00:10"
    # JWT 签名密钥（生产环境务必修改为随机值）
    JWT_SECRET_KEY: str = _DEFAULT_JWT_SECRET
    JWT_ALGORITHM: str = "HS256"
    # 访问令牌有效期（分钟），默认 24 小时
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 小时
    # 刷新令牌有效期（天）：默认 365 天，且每次刷新自动顺延（滑动续期），
    # 只要持续使用即不会自动退出；连续超过该天数未使用才需重新登录
    REFRESH_TOKEN_EXPIRE_DAYS: int = 365
    # 登录失败锁定阈值（次）与锁定时长（分钟）
    LOGIN_MAX_FAILURES: int = 5
    LOGIN_LOCK_MINUTES: int = 15
    # 暴力破解检测：近 N 分钟内同一 IP 失败次数 ≥ 阈值则向管理员告警
    BRUTE_FORCE_WINDOW_MINUTES: int = 30
    BRUTE_FORCE_THRESHOLD: int = 10
    # mysqldump 可执行文件路径（留空则自动从 PATH 查找）
    MYSQLDUMP_PATH: str = ""
    # 体重秤采集：是否在本进程内启动蓝牙扫描（无蓝牙环境请保持 False，自动降级）
    ENABLE_SCALE_COLLECTOR: bool = False
    # 体重数据归属用户 id（0 表示自动取第一个用户）
    SCALE_USER_ID: int = 0
    # 体重秤设备名前缀（不区分大小写，默认识别蚂蚁阿福 AFU 秤）
    SCALE_NAME_PREFIX: str = "AFU"
    # 体成分估算兜底资料：身高（厘米）、年龄（岁）、性别（male/female）
    SCALE_HEIGHT_CM: int = 173
    SCALE_AGE: int = 25
    SCALE_SEX: str = "male"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    """加载配置并校验 JWT 密钥。

    本地开发环境（ENVIRONMENT 为 development/dev/local/test）允许使用默认密钥，
    仅输出警告；其他环境视为生产，若 JWT_SECRET_KEY 为空或仍为默认值则直接抛错，
    让进程启动失败，避免用公开默认密钥签发令牌。

    Returns:
        校验通过的 Settings 实例。

    Raises:
        RuntimeError: 非开发环境下 JWT_SECRET_KEY 缺失或仍为默认值。
    """
    s = Settings()
    env = s.ENVIRONMENT.strip().lower()
    if env in _DEV_ENVIRONMENTS:
        # 仅在本地开发环境告警，不阻断启动
        if s.JWT_SECRET_KEY == _DEFAULT_JWT_SECRET:
            warnings.warn(
                "JWT_SECRET_KEY 仍为默认不安全值！生产环境必须在 .env 中设置为随机长字符串。",
                stacklevel=2,
            )
        return s
    if not s.JWT_SECRET_KEY.strip() or s.JWT_SECRET_KEY == _DEFAULT_JWT_SECRET:
        raise RuntimeError(
            f"ENVIRONMENT={s.ENVIRONMENT} 为非开发环境，"
            "JWT_SECRET_KEY 必须设置为随机长字符串，禁止使用空值或默认密钥。"
        )
    return s


settings = get_settings()
