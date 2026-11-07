"""health 域响应模型约束放宽回归。

只放宽响应侧校验：历史/手环越界数据（血氧>100、心率>250、0 克饮食、
旧版 result 取值、0 盒购药）必须能正常读出；请求侧校验保持不变。
"""

from datetime import date

import pytest
from pydantic import ValidationError

from app.models import HealthDiet
from app.schemas.health import (
    CheckupCreate,
    CheckupRead,
    DietCreate,
    DietRead,
    MedPurchaseCreate,
    MedPurchaseRead,
    VitalsSleepCreate,
    VitalsSleepRead,
)
from read_relax_helpers import make_client, read_base

_READ_CASES = [
    (
        VitalsSleepRead,
        {
            "record_date": date(2023, 1, 1),
            "blood_oxygen": 150,
            "sleep_quality": 12,
            "hr_max": 300,
            "hr_source": "bluetooth-band-extra-long",
        },
        {
            "blood_oxygen": 150,
            "sleep_quality": 12,
            "hr_max": 300,
            "hr_source": "bluetooth-band-extra-long",
        },
    ),
    (
        DietRead,
        {
            "record_date": date(2023, 1, 1),
            "meal_type": "brunch",
            "food_name": "米饭",
            "weight_g": 0,
            "calories": 520,
        },
        {"meal_type": "brunch", "weight_g": 0},
    ),
    (
        CheckupRead,
        {"check_date": date(2023, 1, 1), "item_name": "血红蛋白", "result": "偏高"},
        {"result": "偏高"},
    ),
    (
        MedPurchaseRead,
        {
            "buy_date": date(2023, 1, 1),
            "medicine_name": "布洛芬",
            "quantity": 0,
            "unit_price": 12.5,
        },
        {"quantity": 0},
    ),
]

_CREATE_CASES = [
    (VitalsSleepCreate, {"record_date": date(2026, 11, 7), "blood_oxygen": 150}),
    (VitalsSleepCreate, {"record_date": date(2026, 11, 7), "hr_max": 300}),
    (VitalsSleepCreate, {"record_date": date(2026, 11, 7), "sleep_quality": 12}),
    (DietCreate, {
        "record_date": date(2026, 11, 7),
        "meal_type": "lunch",
        "food_name": "米饭",
        "weight_g": 0,
    }),
    (DietCreate, {
        "record_date": date(2026, 11, 7),
        "meal_type": "brunch",
        "food_name": "米饭",
        "weight_g": 100,
    }),
    (CheckupCreate, {
        "check_date": date(2026, 11, 7),
        "item_name": "血红蛋白",
        "result": "偏高",
    }),
    (MedPurchaseCreate, {
        "buy_date": date(2026, 11, 7),
        "medicine_name": "布洛芬",
        "quantity": 0,
        "unit_price": 12.5,
    }),
]


@pytest.mark.parametrize(
    "read_schema,payload,expected",
    _READ_CASES,
    ids=[case[0].__name__ for case in _READ_CASES],
)
def test_health_read_accepts_historical_out_of_range(read_schema, payload, expected):
    """health 历史越界值可正常序列化，且数值原样保留。"""
    obj = read_schema.model_validate({**read_base(), **payload})
    for key, value in expected.items():
        assert getattr(obj, key) == value


@pytest.mark.parametrize(
    "create_schema,payload", _CREATE_CASES,
    ids=[f"{c[0].__name__}-{i}" for i, c in enumerate(_CREATE_CASES)],
)
def test_health_create_still_rejects_violation(create_schema, payload):
    """health 请求侧校验未放松。"""
    with pytest.raises(ValidationError):
        create_schema.model_validate(payload)


def _diet_payload(weight_g: float) -> dict:
    """构造健康饮食的 HTTP 请求体。"""
    return {
        "record_date": "2026-11-07",
        "meal_type": "lunch",
        "food_name": "米饭",
        "weight_g": weight_g,
    }


def test_health_create_endpoint_still_returns_422(db_session):
    """新增饮食接口对 weight_g=0 返回 422。"""
    client = make_client(
        db_session,
        prefix="/diet",
        model=HealthDiet,
        create_schema=DietCreate,
        read_schema=DietRead,
    )
    resp = client.post("/diet", json=_diet_payload(0))
    assert resp.status_code == 422, resp.text


def test_health_update_endpoint_still_returns_422(db_session):
    """更新接口复用 Create 模型，weight_g=0 同样返回 422。"""
    row = HealthDiet(
        user_id=1,
        record_date=date(2026, 11, 7),
        meal_type="lunch",
        food_name="米饭",
        weight_g=100,
        calories=520,
    )
    db_session.add(row)
    db_session.flush()
    client = make_client(
        db_session,
        prefix="/diet",
        model=HealthDiet,
        create_schema=DietCreate,
        read_schema=DietRead,
    )
    resp = client.put(f"/diet/{row.id}", json=_diet_payload(0))
    assert resp.status_code == 422, resp.text
