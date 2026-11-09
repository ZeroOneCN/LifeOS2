"""账单应付额变更联动测试：PUT /finance/loan-bills/{id} 改 amount 后重算 paid_amount / status。"""

from datetime import date
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.api.routes.finance.loans import router as loans_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import FinanceLoanBill, FinanceRepayment


def _make_client(db) -> TestClient:
    """构造挂载网贷借还路由的测试客户端。

    Args:
        db: 已绑定测试会话的 Session 实例。

    Returns:
        覆盖了数据库与当前用户的 TestClient。
    """
    app = FastAPI()
    app.include_router(loans_router)

    def _override_db():
        """把路由的数据库依赖指到测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    return TestClient(app)


def _seed_bill(
    db,
    *,
    amount: float,
    paid_amount: float,
    status: str,
    repay: float,
    discount: float = 0.0,
) -> FinanceLoanBill:
    """插入一条账单及对应还款明细。

    Args:
        db: 测试会话。
        amount: 应付额（实付口径）。
        paid_amount: 存储的已还额。
        status: 存储状态。
        repay: 还款明细的实付金额。
        discount: 还款明细另计的优惠金额。

    Returns:
        已 flush 的账单实体。
    """
    bill = FinanceLoanBill(
        user_id=1,
        platform_id=None,
        bill_month=date(2026, 11, 1),
        due_date=date(2026, 11, 20),
        amount=amount,
        interest=0,
        paid_amount=paid_amount,
        status=status,
        grace_applied=False,
        note="测试账单",
    )
    db.add(bill)
    db.flush()
    if repay:
        db.add(
            FinanceRepayment(
                user_id=1,
                bill_id=bill.id,
                repay_date=date(2026, 11, 5),
                amount=repay,
                discount=discount,
                note=None,
            )
        )
        db.flush()
    return bill


def _payload(bill: FinanceLoanBill, **overrides) -> dict:
    """按前端编辑弹窗的完整字段构造 PUT 请求体。

    Args:
        bill: 账单实体。
        **overrides: 需要覆盖的字段。

    Returns:
        可直接作为 PUT 请求体的字段字典。
    """
    data = {
        "platform_id": bill.platform_id,
        "bill_month": bill.bill_month.isoformat(),
        "due_date": bill.due_date.isoformat() if bill.due_date else None,
        "amount": bill.amount,
        "interest": bill.interest,
        "paid_amount": bill.paid_amount,
        "status": bill.status,
        "grace_applied": bool(bill.grace_applied),
        "note": bill.note,
    }
    data.update(overrides)
    return data


def test_update_amount_up_from_cleared_returns_partial(db_session):
    """改大应付额后已还额不变，状态由 cleared 回到 partial。"""
    bill = _seed_bill(
        db_session, amount=100, paid_amount=100, status="cleared", repay=100
    )
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/loan-bills/{bill.id}",
        json=_payload(bill, amount=120, paid_amount=100, status="cleared"),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["paid_amount"] == 100
    assert body["status"] == "partial"


def test_update_amount_below_paid_stays_cleared(db_session):
    """改小到低于已还额时状态变 cleared，且已还额按还款明细保持不变。"""
    bill = _seed_bill(
        db_session, amount=100, paid_amount=50, status="partial", repay=45, discount=5
    )
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/loan-bills/{bill.id}",
        json=_payload(bill, amount=40),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["paid_amount"] == 50  # Σ(amount + discount) = 45 + 5
    assert body["status"] == "cleared"


def test_update_amount_exactly_equal_paid_is_cleared(db_session):
    """改到恰好等于已还额时容差内判定为 cleared。"""
    bill = _seed_bill(
        db_session, amount=100, paid_amount=50, status="partial", repay=50
    )
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/loan-bills/{bill.id}",
        json=_payload(bill, amount=50),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["paid_amount"] == 50
    assert body["status"] == "cleared"


def test_update_other_fields_keeps_paid_amount(db_session):
    """只改备注等非应付额字段时不触发重算，保留手工维护的已还额。"""
    bill = _seed_bill(
        db_session, amount=100, paid_amount=30, status="partial", repay=50
    )
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/loan-bills/{bill.id}",
        json=_payload(bill, note="改个备注"),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["paid_amount"] == 30
    assert body["status"] == "partial"


def _repay_payload(bill_id: int, payable: float, discount: float = 0.0) -> dict:
    """构造还款写入请求体：只传应付与优惠，实付由后端推导。

    Args:
        bill_id: 关联账单 id。
        payable: 本次应付（含优惠）。
        discount: 优惠金额。

    Returns:
        可直接作为 POST/PUT 请求体的字段字典。
    """
    return {
        "bill_id": bill_id,
        "repay_date": date(2026, 11, 7).isoformat(),
        "payable": payable,
        "discount": discount,
        "method": "微信",
        "note": None,
    }


def test_create_repayment_derives_actual_from_payable(db_session):
    """新增还款：后端按「应付 − 优惠」落库实付，并按应付冲减账单。"""
    bill = _seed_bill(db_session, amount=100, paid_amount=0, status="pending", repay=0)
    client = _make_client(db_session)

    resp = client.post(
        "/finance/repayments",
        json=_repay_payload(bill.id, payable=100, discount=10),
    )

    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["amount"] == 90  # 实付
    assert body["payable"] == 100
    assert body["discount"] == 10
    db_session.refresh(bill)
    assert bill.paid_amount == 100  # Σ(实付 + 优惠)
    assert bill.status == "cleared"

    listed = client.get(f"/finance/repayments?bill_id={bill.id}")
    assert listed.status_code == 200, listed.text
    assert listed.json()[0]["payable"] == 100


def test_create_repayment_rejects_discount_above_payable(db_session):
    """优惠大于应付时拒绝写入，账单不被冲减。"""
    bill = _seed_bill(db_session, amount=100, paid_amount=0, status="pending", repay=0)
    client = _make_client(db_session)

    resp = client.post(
        "/finance/repayments",
        json=_repay_payload(bill.id, payable=100, discount=101),
    )

    assert resp.status_code == 400
    db_session.refresh(bill)
    assert bill.paid_amount == 0
    assert bill.status == "pending"


def test_update_repayment_recomputes_actual_and_bill(db_session):
    """编辑还款：改应付与优惠后重算实付与账单已还额。"""
    bill = _seed_bill(
        db_session, amount=100, paid_amount=100, status="cleared", repay=90, discount=10
    )
    repayment = db_session.scalars(
        select(FinanceRepayment).where(FinanceRepayment.bill_id == bill.id)
    ).all()[0]
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/repayments/{repayment.id}",
        json=_repay_payload(bill.id, payable=95, discount=20),
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["amount"] == 75
    assert body["payable"] == 95
    db_session.refresh(bill)
    assert bill.paid_amount == 95
    assert bill.status == "partial"


def test_update_repayment_switches_bill_and_resyncs_both(db_session):
    """编辑时换绑账单：新旧账单的已还额都要重算，旧账单不能残留。"""
    old_bill = _seed_bill(
        db_session, amount=100, paid_amount=100, status="cleared", repay=90, discount=10
    )
    new_bill = _seed_bill(
        db_session, amount=200, paid_amount=0, status="pending", repay=0
    )
    repayment = db_session.scalars(
        select(FinanceRepayment).where(FinanceRepayment.bill_id == old_bill.id)
    ).all()[0]
    client = _make_client(db_session)

    resp = client.put(
        f"/finance/repayments/{repayment.id}",
        json=_repay_payload(new_bill.id, payable=50),
    )

    assert resp.status_code == 200, resp.text
    db_session.refresh(old_bill)
    db_session.refresh(new_bill)
    assert old_bill.paid_amount == 0
    assert old_bill.status == "pending"
    assert new_bill.paid_amount == 50
    assert new_bill.status == "partial"
