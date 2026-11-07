"""lifestyle 域响应模型约束放宽回归。

历史物品旧状态/来源、号卡与银行卡的旧计费/状态取值、超出 1..31 的账单日
都必须能正常读出；请求侧校验保持不变。
"""

from datetime import date

import pytest
from pydantic import ValidationError

from app.models import LifestyleItem
from app.schemas.lifestyle import (
    BankCardCreate,
    BankCardRead,
    ItemCreate,
    ItemRead,
    PhoneCardCreate,
    PhoneCardRead,
)
from read_relax_helpers import make_client, read_base

_READ_CASES = [
    (
        ItemRead,
        {
            "item_name": "旧手机",
            "category": "电子",
            "status": "broken",
            "source": "import",
        },
        {"status": "broken", "source": "import"},
    ),
    (
        PhoneCardRead,
        {
            "phone_number": "13800000000",
            "operator": "移动",
            "bill_day": 40,
            "billing_type": "weekly",
            "charge_mode": "yearly",
            "status": "unknown",
        },
        {
            "bill_day": 40,
            "billing_type": "weekly",
            "charge_mode": "yearly",
            "status": "unknown",
        },
    ),
    (
        BankCardRead,
        {
            "card_name": "工资卡",
            "bank": "招行",
            "card_category": "savings",
            "card_form": "plastic",
            "billing_day": 0,
            "due_day": 40,
            "status": "unknown",
        },
        {
            "card_category": "savings",
            "card_form": "plastic",
            "billing_day": 0,
            "due_day": 40,
            "status": "unknown",
        },
    ),
]

_CREATE_CASES = [
    (ItemCreate, {"item_name": "旧手机", "category": "电子", "status": "broken"}),
    (PhoneCardCreate, {
        "phone_number": "13800000000",
        "operator": "移动",
        "bill_day": 40,
    }),
    (BankCardCreate, {"card_name": "工资卡", "bank": "招行", "billing_day": 0}),
]


@pytest.mark.parametrize(
    "read_schema,payload,expected",
    _READ_CASES,
    ids=[case[0].__name__ for case in _READ_CASES],
)
def test_lifestyle_read_accepts_historical_out_of_range(read_schema, payload, expected):
    """lifestyle 历史越界值可正常序列化，且数值原样保留。"""
    obj = read_schema.model_validate({**read_base(), **payload})
    for key, value in expected.items():
        assert getattr(obj, key) == value


@pytest.mark.parametrize(
    "create_schema,payload", _CREATE_CASES,
    ids=[f"{c[0].__name__}-{i}" for i, c in enumerate(_CREATE_CASES)],
)
def test_lifestyle_create_still_rejects_violation(create_schema, payload):
    """lifestyle 请求侧校验未放松。"""
    with pytest.raises(ValidationError):
        create_schema.model_validate(payload)


def test_lifestyle_create_endpoint_still_returns_422(db_session):
    """新增物品接口对 status=broken 返回 422。"""
    client = make_client(
        db_session,
        prefix="/item",
        model=LifestyleItem,
        create_schema=ItemCreate,
        read_schema=ItemRead,
    )
    resp = client.post(
        "/item",
        json={"item_name": "旧手机", "category": "电子", "status": "broken"},
    )
    assert resp.status_code == 422, resp.text
