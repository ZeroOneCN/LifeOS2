"""话费摊销纯函数测试：按月天数与逐日金额精度。"""

from datetime import date

import pytest

from app.services.phone_billing import daily_amounts, days_in_month


@pytest.mark.parametrize(
    "day, expected",
    [
        (date(2023, 2, 15), 28),  # 平年 2 月
        (date(2024, 2, 15), 29),  # 闰年 2 月
        (date(2023, 4, 15), 30),  # 小月
        (date(2023, 1, 15), 31),  # 大月
        (date(2023, 12, 31), 31),  # 年末
    ],
)
def test_days_in_month(day, expected):
    """各月天数应与日历一致（含闰年）。"""
    assert days_in_month(day) == expected


@pytest.mark.parametrize("days", [28, 29, 30, 31])
def test_daily_amounts_sum_is_exact(days):
    """除不尽时最后一天补差，逐日合计必须精确等于月租。"""
    fee = 100.0
    amounts = daily_amounts(fee, days)
    assert len(amounts) == days
    assert round(sum(amounts), 2) == pytest.approx(fee, abs=0.001)
    # 前 days-1 天等额，最后一天补差
    assert len(set(amounts[:-1])) <= 1
    assert amounts[-1] == round(fee - amounts[0] * (days - 1), 2)


@pytest.mark.parametrize(
    "fee, days, expected_last",
    [
        (100.0, 3, 33.34),  # 33.33 * 2 = 66.66，最后一天补 33.34
        (10.0, 3, 3.34),
        (28.0, 28, 1.0),  # 整除
    ],
)
def test_daily_amounts_last_day_compensates(fee, days, expected_last):
    """最后一天金额应为「月租 - 前 N-1 天合计」，保证总账不差分。"""
    assert daily_amounts(fee, days)[-1] == expected_last


def test_daily_amounts_zero_or_negative():
    """月租为 0/负数或天数非法时返回全 0，不应产生负数扣费。"""
    assert daily_amounts(0.0, 31) == [0.0] * 31
    assert daily_amounts(-5.0, 31) == [0.0] * 31
    assert daily_amounts(30.0, 0) == []
    assert daily_amounts(30.0, -1) == []


def test_daily_amounts_negative_fee_clamped():
    """负数月租先夹紧为 0，避免出现负扣费。"""
    assert daily_amounts(-100.0, 30) == [0.0] * 30
