"""债务本金变更联动测试：PUT 修改 amount 后 remaining / status 必须重算。"""

from datetime import date
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes.finance.debts import router as debts_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import FinanceDebt, FinanceDebtPayment


def _make_client(db) -> TestClient:
    """构造挂载债务路由的测试客户端。

    Args:
        db: 已绑定测试会话的 Session 实例。

    Returns:
        覆盖了数据库与当前用户的 TestClient。
    """
    app = FastAPI()
    app.include_router(debts_router)

    def _override_db():
        """把路由的数据库依赖指到测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    return TestClient(app)


def _seed_debt(
    db,
    *,
    amount: float,
    remaining: float,
    direction: str = "borrow",
    paid: float = 0.0,
    discount: float = 0.0,
) -> FinanceDebt:
    """插入一条债务（可附带一笔还款明细）。

    Args:
        db: 测试会话。
        amount: 本金（清账额）。
        remaining: 初始剩余（模拟用户手工维护值）。
        direction: borrow=借入 / lend=借出。
        paid: 还款明细的清账额（含优惠）。
        discount: 还款明细中的优惠金额。

    Returns:
        已 flush 的债务实体。
    """
    debt = FinanceDebt(
        user_id=1,
        debt_date=date(2026, 11, 1),
        name="测试债务",
        direction=direction,
        counterparty="张三",
        amount=amount,
        remaining=remaining,
        status="active",
    )
    db.add(debt)
    db.flush()
    if paid:
        db.add(
            FinanceDebtPayment(
                user_id=1,
                debt_id=debt.id,
                repay_date=date(2026, 11, 2),
                amount=paid,
                discount=discount,
            )
        )
        db.flush()
    return debt


def _payload(debt: FinanceDebt, **overrides) -> dict:
    """按前端编辑弹窗的完整字段构造 PUT 请求体。

    Args:
        debt: 债务实体。
        **overrides: 需要覆盖的字段。

    Returns:
        可直接作为 PUT 请求体的字段字典。
    """
    data = {
        "debt_date": debt.debt_date.isoformat(),
        "name": debt.name,
        "direction": debt.direction,
        "counterparty": debt.counterparty,
        "amount": debt.amount,
        "remaining": debt.remaining,
        "interest_rate": None,
        "interest_total": 0,
        "channel": "现金",
        "due_date": None,
        "status": debt.status,
        "note": debt.note,
    }
    data.update(overrides)
    return data


def test_update_amount_recalculates_remaining(db_session):
    """本金改大后剩余按全部还款明细重算：1800 − 200 = 1600。"""
    debt = _seed_debt(db_session, amount=1500, remaining=1300, paid=200)
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/debts/{debt.id}",
        json=_payload(debt, amount=1800, remaining=1300),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["remaining"] == 1600
    assert body["status"] == "active"


def test_update_amount_below_paid_settles_debt(db_session):
    """本金改到低于已还额时，剩余归零且状态变为 settled。"""
    debt = _seed_debt(db_session, amount=1500, remaining=300, paid=1200)
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/debts/{debt.id}",
        json=_payload(debt, amount=1150, remaining=300),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["remaining"] == 0
    assert body["status"] == "settled"


def test_update_amount_recalculates_for_lend_direction(db_session):
    """借出方向与借入方向口径一致：1800 − 200 = 1600，保持进行中。"""
    debt = _seed_debt(
        db_session, amount=1500, remaining=1300, paid=200, direction="lend"
    )
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/debts/{debt.id}",
        json=_payload(debt, amount=1800),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["remaining"] == 1600
    assert body["status"] == "active"


def test_update_other_fields_keeps_remaining(db_session):
    """只改备注等非本金字段时不触发重算，保留用户手工维护的剩余。"""
    debt = _seed_debt(db_session, amount=1500, remaining=1100, paid=200)
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/debts/{debt.id}",
        json=_payload(debt, note="改个备注"),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["remaining"] == 1100
    assert body["status"] == "active"
