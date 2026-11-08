"""外汇备注输出口径：对外输出与数据库原文一致，不替换字段名、不改写数值。"""

from datetime import date

from app.api.routes.investment.forex import _apply_payload, _read
from app.models import InvestmentForex
from app.schemas.investment import ForexCreate


def _trade(note: str | None) -> InvestmentForex:
    """构造一条带备注的已平仓交易。"""
    return InvestmentForex(
        user_id=1,
        trade_date=date.today(),
        symbol="XAUUSD",
        order_type="buy",
        open_price=1.0,
        lot_size=0.1,
        commission=0.0,
        overnight_fee=0.0,
        status="closed",
        note=note,
    )


def test_read_returns_raw_machine_note(db_session):
    """导入备注原样输出，保留 ID/TP/SL 字段名与数值。"""
    obj = _trade("ID:169756053 | TP:4672.0 | SL:4300.0")
    db_session.add(obj)
    db_session.flush()

    assert _read(obj).note == "ID:169756053 | TP:4672.0 | SL:4300.0"


def test_read_returns_raw_human_note(db_session):
    """人工备注同样原样输出。"""
    obj = _trade("mobile-b5-verify")
    db_session.add(obj)
    db_session.flush()

    assert _read(obj).note == "mobile-b5-verify"


def test_read_keeps_empty_note(db_session):
    """无备注时仍为 None，不补占位文本。"""
    obj = _trade(None)
    db_session.add(obj)
    db_session.flush()

    assert _read(obj).note is None


def test_update_stores_note_as_is(db_session):
    """更新接口按提交内容保存备注，不做任何改写。"""
    obj = _trade("ID:123 | TP:4315.0")
    db_session.add(obj)
    db_session.flush()

    payload = ForexCreate(
        trade_date=date.today(),
        symbol="XAUUSD",
        order_type="buy",
        open_price=1.0,
        lot_size=0.1,
        note="ID:123 | SL:4300.0",
    )
    _apply_payload(obj, payload)

    assert obj.note == "ID:123 | SL:4300.0"
