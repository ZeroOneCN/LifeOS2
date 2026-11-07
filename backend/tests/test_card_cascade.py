"""卡片删除级联清理测试：删卡后关联流水为 0，其它卡数据不受影响。"""

from datetime import date
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes.lifestyle.cards import router as cards_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (
    LifestyleCardBill,
    LifestylePhoneCard,
    LifestylePhoneLedger,
    LifestylePhoneRecharge,
)


def _make_client(db) -> TestClient:
    """构造挂载卡片路由的测试客户端。

    Args:
        db: 已绑定测试会话的 Session 实例。

    Returns:
        覆盖了数据库与当前用户的 TestClient。
    """
    app = FastAPI()
    app.include_router(cards_router)

    def _override_db():
        """把路由的数据库依赖指到测试会话。"""
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
    return TestClient(app)


def _seed_phone_card(db, number: str) -> LifestylePhoneCard:
    """插入一张手机号卡，并挂上流水 / 账单 / 旧版充值各一条。

    Args:
        db: 测试会话。
        number: 手机号。

    Returns:
        已 flush 的手机号卡实体。
    """
    card = LifestylePhoneCard(
        user_id=1,
        phone_number=number,
        operator="测试运营商",
        balance=10,
        opening_balance=0,
        monthly_fee=30,
        billing_type="monthly",
        charge_mode="monthly",
        status="active",
    )
    db.add(card)
    db.flush()
    db.add(
        LifestylePhoneLedger(
            user_id=1,
            phone_card_id=card.id,
            entry_date=date(2026, 11, 1),
            entry_type="recharge",
            amount=10,
            source="manual",
        )
    )
    db.add(
        LifestyleCardBill(
            user_id=1,
            phone_card_id=card.id,
            bill_month=date(2026, 11, 1),
            amount=30,
            paid=True,
        )
    )
    db.add(
        LifestylePhoneRecharge(
            user_id=1,
            phone_card_id=card.id,
            amount=10,
            recharge_date=date(2026, 11, 2),
        )
    )
    db.flush()
    return card


def _child_counts(db, card_id: int) -> tuple[int, int, int]:
    """统计某张手机卡名下的流水 / 账单 / 旧版充值条数。

    Args:
        db: 测试会话。
        card_id: 手机号卡 id。

    Returns:
        (流水条数, 账单条数, 旧版充值条数)。
    """
    ledger = db.query(LifestylePhoneLedger).filter_by(phone_card_id=card_id).count()
    bill = db.query(LifestyleCardBill).filter_by(phone_card_id=card_id).count()
    recharge = db.query(LifestylePhoneRecharge).filter_by(phone_card_id=card_id).count()
    return ledger, bill, recharge


def test_delete_phone_card_removes_related_flows(db_session):
    """单条删除手机卡后其名下流水清零，其它卡的数据保持完整。"""
    keep = _seed_phone_card(db_session, "13800000001")
    doomed = _seed_phone_card(db_session, "13800000002")
    assert _child_counts(db_session, doomed.id) == (1, 1, 1)
    client = _make_client(db_session)

    resp = client.delete(f"/lifestyle/phone-cards/{doomed.id}")

    assert resp.status_code == 204, resp.text
    assert db_session.get(LifestylePhoneCard, doomed.id) is None
    assert _child_counts(db_session, doomed.id) == (0, 0, 0)
    assert db_session.get(LifestylePhoneCard, keep.id) is not None
    assert _child_counts(db_session, keep.id) == (1, 1, 1)


def test_batch_delete_phone_cards_removes_related_flows(db_session):
    """批量删除路径同样清理关联流水，且不影响未删除的卡。"""
    keep = _seed_phone_card(db_session, "13800000003")
    doomed_a = _seed_phone_card(db_session, "13800000004")
    doomed_b = _seed_phone_card(db_session, "13800000005")
    client = _make_client(db_session)

    resp = client.request(
        "DELETE",
        "/lifestyle/phone-cards/batch",
        json={"ids": [doomed_a.id, doomed_b.id]},
    )

    assert resp.status_code == 204, resp.text
    assert _child_counts(db_session, doomed_a.id) == (0, 0, 0)
    assert _child_counts(db_session, doomed_b.id) == (0, 0, 0)
    assert _child_counts(db_session, keep.id) == (1, 1, 1)
