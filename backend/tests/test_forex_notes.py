"""外汇备注展示口径：机器串转可读标签，数据库原始备注不被改写。"""

from datetime import date

from app.api.routes.investment.forex import _apply_payload, _read, clean_note
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


def test_clean_note_maps_all_machine_tokens():
    """ID/TP/SL 机器串全部转成中文标签。"""
    assert clean_note("ID:169756053 | TP:4672.0 | SL:4300.0") == (
        "订单号 169756053 · 止盈价 4672.0 · 止损价 4300.0"
    )


def test_clean_note_maps_single_token():
    """只有订单号时同样可读。"""
    assert clean_note("ID:169476058") == "订单号 169476058"


def test_clean_note_keeps_human_note_unchanged():
    """没有机器串的人工备注原样返回。"""
    assert clean_note("mobile-b5-verify") == "mobile-b5-verify"


def test_clean_note_handles_empty_values():
    """空备注返回 None，不产生占位文本。"""
    assert clean_note(None) is None
    assert clean_note("   ") is None


def test_clean_note_degrades_without_raising():
    """格式异常时不抛异常，未识别的片段原样保留。"""
    assert clean_note("ID: | TP:abc") == "ID: · 止盈价 abc"


def test_read_hides_machine_note(db_session):
    """读接口输出可读备注，机器串不外露。"""
    obj = _trade("ID:123 | TP:4315.0")
    db_session.add(obj)
    db_session.flush()

    assert _read(obj).note == "订单号 123 · 止盈价 4315.0"
    # 数据库原文未被改写
    assert obj.note == "ID:123 | TP:4315.0"


def test_update_keeps_raw_note_when_readable_note_sent_back(db_session):
    """客户端回传可读备注时保留原始串，避免丢失导入订单号。"""
    obj = _trade("ID:123 | TP:4315.0")
    db_session.add(obj)
    db_session.flush()

    payload = ForexCreate(
        trade_date=date.today(),
        symbol="XAUUSD",
        order_type="buy",
        open_price=1.0,
        lot_size=0.1,
        note="订单号 123 · 止盈价 4315.0",
    )
    _apply_payload(obj, payload)

    assert obj.note == "ID:123 | TP:4315.0"


def test_update_replaces_note_with_user_edit(db_session):
    """用户真正改写备注时按新内容保存。"""
    obj = _trade("ID:123 | TP:4315.0")
    db_session.add(obj)
    db_session.flush()

    payload = ForexCreate(
        trade_date=date.today(),
        symbol="XAUUSD",
        order_type="buy",
        open_price=1.0,
        lot_size=0.1,
        note="手工标注：突破追单",
    )
    _apply_payload(obj, payload)

    assert obj.note == "手工标注：突破追单"
