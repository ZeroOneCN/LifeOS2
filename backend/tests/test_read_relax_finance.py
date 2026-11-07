"""finance 域响应模型约束放宽回归。

历史平台配置（天数为 0 或 >31、容时 >15 天）、旧状态取值、0 元还款/清账、
0 汇率都必须能正常读出；请求侧校验保持不变。
"""

from datetime import date

import pytest
from pydantic import ValidationError

from app.models import FinanceRepayment
from app.schemas.finance import (
    CurrencyCreate,
    CurrencyRead,
    DebtCreate,
    DebtPaymentCreate,
    DebtPaymentRead,
    DebtRead,
    LoanBillCreate,
    LoanBillRead,
    LoanPlatformCreate,
    LoanPlatformRead,
    PlanCreate,
    PlanRead,
    RepaymentCreate,
    RepaymentRead,
)
from read_relax_helpers import make_client, read_base

_READ_CASES = [
    (
        LoanPlatformRead,
        {
            "name": "花呗",
            "bill_day": 40,
            "due_day": 0,
            "grace_days": 30,
            "grace_hour": 25,
            "penalty_rate": 9,
        },
        {
            "bill_day": 40,
            "due_day": 0,
            "grace_days": 30,
            "grace_hour": 25,
            "penalty_rate": 9,
        },
    ),
    (
        LoanBillRead,
        {"bill_month": date(2023, 1, 1), "amount": 100, "status": "overdue"},
        {"status": "overdue"},
    ),
    (
        RepaymentRead,
        {"repay_date": date(2023, 1, 1), "amount": 0},
        {"amount": 0},
    ),
    (
        PlanRead,
        {
            "plan_date": date(2023, 1, 1),
            "plan_type": "save",
            "title": "旅行基金",
            "status": "paused",
        },
        {"status": "paused"},
    ),
    (
        DebtRead,
        {
            "debt_date": date(2023, 1, 1),
            "name": "借给同事",
            "direction": "other",
            "amount": 500,
            "channel": "很长的渠道名称超过十六个字符啊啊啊",
            "status": "closed",
        },
        {
            "direction": "other",
            "channel": "很长的渠道名称超过十六个字符啊啊啊",
            "status": "closed",
        },
    ),
    (
        DebtPaymentRead,
        {"repay_date": date(2023, 1, 1), "amount": 0, "debt_id": 1},
        {"amount": 0},
    ),
    (
        CurrencyRead,
        {"currency": "JPY", "rate_to_cny": 0},
        {"rate_to_cny": 0},
    ),
]

_CREATE_CASES = [
    (LoanPlatformCreate, {"name": "花呗", "bill_day": 40}),
    (LoanBillCreate, {
        "bill_month": date(2026, 11, 1),
        "amount": 100,
        "status": "overdue",
    }),
    (RepaymentCreate, {"repay_date": date(2026, 11, 7), "amount": 0}),
    (PlanCreate, {
        "plan_date": date(2026, 11, 7),
        "plan_type": "save",
        "title": "旅行基金",
        "status": "paused",
    }),
    (DebtCreate, {
        "debt_date": date(2026, 11, 7),
        "name": "借给同事",
        "direction": "other",
        "amount": 500,
    }),
    (DebtPaymentCreate, {"repay_date": date(2026, 11, 7), "amount": 0}),
    (CurrencyCreate, {"currency": "JPY", "rate_to_cny": 0}),
]


@pytest.mark.parametrize(
    "read_schema,payload,expected",
    _READ_CASES,
    ids=[case[0].__name__ for case in _READ_CASES],
)
def test_finance_read_accepts_historical_out_of_range(read_schema, payload, expected):
    """finance 历史越界值可正常序列化，且数值原样保留。"""
    obj = read_schema.model_validate({**read_base(), **payload})
    for key, value in expected.items():
        assert getattr(obj, key) == value


@pytest.mark.parametrize(
    "create_schema,payload", _CREATE_CASES,
    ids=[f"{c[0].__name__}-{i}" for i, c in enumerate(_CREATE_CASES)],
)
def test_finance_create_still_rejects_violation(create_schema, payload):
    """finance 请求侧校验未放松。"""
    with pytest.raises(ValidationError):
        create_schema.model_validate(payload)


def test_finance_create_endpoint_still_returns_422(db_session):
    """新增还款接口对 amount=0 返回 422。"""
    client = make_client(
        db_session,
        prefix="/repayment",
        model=FinanceRepayment,
        create_schema=RepaymentCreate,
        read_schema=RepaymentRead,
    )
    resp = client.post("/repayment", json={"repay_date": "2026-11-07", "amount": 0})
    assert resp.status_code == 422, resp.text
