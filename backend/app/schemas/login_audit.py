from datetime import datetime

from pydantic import BaseModel, ConfigDict


class LoginAuditRead(BaseModel):
    """登录审计记录（用于前端展示）。"""

    model_config = ConfigDict(from_attributes=True)

    id: int
    account: str
    user_id: int | None
    result: str  # success / fail / locked
    failure_reason: str | None
    ip_address: str | None
    user_agent: str | None
    lock_triggered: bool
    created_at: datetime
