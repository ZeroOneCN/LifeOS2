from sqlalchemy import Integer
from sqlalchemy.orm import Mapped, mapped_column


class UserOwned:
    """多用户归属 mixin：所有业务表通过它挂 user_id 归属当前登录用户。"""

    user_id: Mapped[int] = mapped_column(Integer, index=True, nullable=False)