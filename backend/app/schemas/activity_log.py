from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ActivityLogRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    action: str
    module: str
    resource_type: str
    resource_id: int | None
    summary: str | None
    detail: str | None
    ip: str | None
    created_at: datetime
