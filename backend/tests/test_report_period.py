"""报告统计区间解析测试：天数回溯、起止颠倒与单日区间。"""

from datetime import date

from app.services.report_period import resolve_period


def test_default_days_backtrack():
    """默认近 30 天应包含今天在内共 30 天。"""
    end = date(2023, 5, 20)
    start, got_end, label = resolve_period(days=30, end_date=end)
    assert got_end == end
    assert start == date(2023, 4, 21)
    assert (got_end - start).days == 29
    assert label == "2023-04-21 ~ 2023-05-20"


def test_days_one_is_today_only():
    """days=1 时区间收缩为单日（start=end）。"""
    end = date(2023, 5, 20)
    start, got_end, label = resolve_period(days=1, end_date=end)
    assert start == end
    assert label == "2023-05-20 ~ 2023-05-20"


def test_start_after_end_is_swapped():
    """start 晚于 end 时自动交换，且 label 同步纠正。"""
    start, end, label = resolve_period(
        start_date=date(2023, 6, 1), end_date=date(2023, 5, 1)
    )
    assert start == date(2023, 5, 1)
    assert end == date(2023, 6, 1)
    assert label == "2023-05-01 ~ 2023-06-01"


def test_explicit_range_ignores_days():
    """显式传入起止日期时不受 days 影响。"""
    start, end, _ = resolve_period(
        days=7, start_date=date(2023, 1, 1), end_date=date(2023, 3, 1)
    )
    assert (start, end) == (date(2023, 1, 1), date(2023, 3, 1))


def test_end_date_defaults_to_today():
    """未传结束日时以今天为终点，起点为今天往前 days-1 天。"""
    start, end, _ = resolve_period(days=7)
    assert end == date.today()
    assert (end - start).days == 6
