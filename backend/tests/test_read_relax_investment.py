"""investment 域响应模型约束放宽回归。

历史外汇订单的旧方向/状态取值、旧基金流水类型都必须能正常读出；
请求侧校验保持不变。
"""

from datetime import date

import pytest
from pydantic import ValidationError

from app.models import InvestmentForex
from app.schemas.investment import (
    ForexCreate,
    ForexRead,
    FundCreate,
    FundRead,
)
from read_relax_helpers import make_client, read_base

_READ_CASES = [
    (
        ForexRead,
        {
            "trade_date": date(2023, 1, 1),
            "symbol": "EURUSD",
            "order_type": "hold",
            "open_price": 1.1,
            "lot_size": 1,
            "status": "pending",
        },
        {"order_type": "hold", "status": "pending"},
    ),
    (
        FundRead,
        {"record_type": "bonus", "amount": 10, "record_date": date(2023, 1, 1)},
        {"record_type": "bonus"},
    ),
]

_CREATE_CASES = [
    (ForexCreate, {
        "trade_date": date(2026, 11, 7),
        "symbol": "EURUSD",
        "order_type": "hold",
        "open_price": 1.1,
        "lot_size": 1,
    }),
    (FundCreate, {
        "record_type": "bonus",
        "amount": 10,
        "record_date": date(2026, 11, 7),
    }),
]


@pytest.mark.parametrize(
    "read_schema,payload,expected",
    _READ_CASES,
    ids=[case[0].__name__ for case in _READ_CASES],
)
def test_investment_read_accepts_historical_out_of_range(read_schema, payload, expected):
    """investment 历史越界值可正常序列化，且数值原样保留。"""
    obj = read_schema.model_validate({**read_base(), **payload})
    for key, value in expected.items():
        assert getattr(obj, key) == value


@pytest.mark.parametrize(
    "create_schema,payload", _CREATE_CASES,
    ids=[f"{c[0].__name__}-{i}" for i, c in enumerate(_CREATE_CASES)],
)
def test_investment_create_still_rejects_violation(create_schema, payload):
    """investment 请求侧校验未放松。"""
    with pytest.raises(ValidationError):
        create_schema.model_validate(payload)


def test_investment_create_endpoint_still_returns_422(db_session):
    """新增外汇订单接口对 order_type=hold 返回 422。"""
    client = make_client(
        db_session,
        prefix="/forex",
        model=InvestmentForex,
        create_schema=ForexCreate,
        read_schema=ForexRead,
    )
    resp = client.post(
        "/forex",
        json={
            "trade_date": "2026-11-07",
            "symbol": "EURUSD",
            "order_type": "hold",
            "open_price": 1.1,
            "lot_size": 1,
        },
    )
    assert resp.status_code == 422, resp.text
