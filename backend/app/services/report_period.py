"""报告统计区间解析：支持按天数回溯（近7/30/90天）与自定义起止日期。"""
from datetime import date, timedelta


def resolve_period(
    days: int = 30,
    start_date: date | None = None,
    end_date: date | None = None,
) -> tuple[date, date, str]:
    """解析报告统计区间。

    - 提供 start_date 时：使用 [start_date, end_date(默认今天)] 作为自定义区间；
      若 start 晚于 end 则自动交换。
    - 否则：以 end_date(默认今天) 为结束日，向前回溯 (days-1) 天。

    返回 (start, end, label)，label 形如 "YYYY-MM-DD ~ YYYY-MM-DD"。
    """
    end = end_date or date.today()
    if start_date:
        start, end = start_date, end
        if start > end:
            start, end = end, start
    else:
        start = end - timedelta(days=days - 1)
    label = f"{start.isoformat()} ~ {end.isoformat()}"
    return start, end, label
