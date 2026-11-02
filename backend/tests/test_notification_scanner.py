"""提醒扫描日期工具测试：跨月、闰年、跨年与月末夹紧。"""

from datetime import date

from app.services.notification.scanner import (
    _add_months,
    _days_in_month,
    _next_day_of_month,
)


def test_days_in_month():
    """各月天数，含闰年 2 月。"""
    assert _days_in_month(2023, 2) == 28
    assert _days_in_month(2024, 2) == 29
    assert _days_in_month(2023, 4) == 30
    assert _days_in_month(2023, 12) == 31


def test_add_months_various():
    """月中日期加月应保持日号。"""
    assert _add_months(date(2023, 3, 15), 1) == date(2023, 4, 15)
    assert _add_months(date(2023, 3, 15), 3) == date(2023, 6, 15)
    assert _add_months(date(2023, 3, 15), 12) == date(2024, 3, 15)


def test_add_months_jan31_to_feb():
    """1 月 31 日加 1 个月：平年落到 2/28，闰年落到 2/29。"""
    assert _add_months(date(2023, 1, 31), 1) == date(2023, 2, 28)
    assert _add_months(date(2024, 1, 31), 1) == date(2024, 2, 29)


def test_add_months_31_to_small_month():
    """31 号遇到小月应夹紧到该月最后一天。"""
    assert _add_months(date(2023, 5, 31), 1) == date(2023, 6, 30)
    assert _add_months(date(2023, 8, 31), 1) == date(2023, 9, 30)


def test_add_months_year_boundary():
    """12 月加月与跨年、回退到上一年。"""
    assert _add_months(date(2023, 12, 31), 1) == date(2024, 1, 31)
    assert _add_months(date(2023, 1, 31), -1) == date(2022, 12, 31)
    assert _add_months(date(2024, 2, 29), 12) == date(2025, 2, 28)


def test_next_day_of_month_today_and_future():
    """当天即为目标日时返回当天；未来目标日返回本月。"""
    assert _next_day_of_month(date(2023, 1, 31), 31) == date(2023, 1, 31)
    assert _next_day_of_month(date(2023, 1, 15), 31) == date(2023, 1, 31)


def test_next_day_of_month_past_rolls_to_next_month():
    """目标日已过则滚到下月，且按目标日夹紧。"""
    assert _next_day_of_month(date(2023, 1, 5), 1) == date(2023, 2, 1)
    assert _next_day_of_month(date(2023, 1, 20), 31) == date(2023, 1, 31)


def test_next_day_of_month_february_clamp():
    """2 月没有 31 日时夹紧到当月最后一天。"""
    assert _next_day_of_month(date(2023, 2, 1), 31) == date(2023, 2, 28)
    assert _next_day_of_month(date(2024, 2, 1), 31) == date(2024, 2, 29)
    # 闰年 2/28 时「31 号」的下一次出现是该月最后一天 2/29
    assert _next_day_of_month(date(2024, 2, 28), 31) == date(2024, 2, 29)


def test_next_day_of_month_december_to_next_year():
    """12 月目标日已过时滚到次年 1 月。"""
    assert _next_day_of_month(date(2023, 12, 20), 31) == date(2023, 12, 31)
    assert _next_day_of_month(date(2023, 12, 31), 1) == date(2024, 1, 1)
