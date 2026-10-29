# -*- coding: utf-8 -*-
"""蚂蚁阿福体重秤（AFU-WL-TZ-A1）读取与体成分估算。

从 XiaomiWatchBlue/weight 项目并入 LifeOS 后端，供进程内采集器直接调用：

    from app.services.scale import ScaleReader, calculate
"""

from .body_composition import calculate
from .reader import ScaleReader

__all__ = ["ScaleReader", "calculate"]
