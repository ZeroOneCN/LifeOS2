"""财务报告购物明细：平台名映射与单价空值口径用例。"""

from datetime import date

from app.models import FinanceShoppingPlatform, FinanceShoppingRecord
from app.services.finance_report import build_finance_report

START = date(2026, 10, 1)
END = date(2026, 10, 31)
SHOPPING_HEADER = ["日期", "平台", "商品", "规格", "单价", "总价"]


def _record(platform_id: int | None, product: str, total: float,
            unit: float | None) -> FinanceShoppingRecord:
    """构造一条购物记录（只填报告用到的字段）。"""
    return FinanceShoppingRecord(
        user_id=1,
        record_date=date(2026, 10, 8),
        platform_id=platform_id,
        product_name=product,
        spec=None,
        total_price=total,
        unit_price=unit,
    )


def _shopping_rows(db_session) -> list[list[str]]:
    """生成财务报告并取出「购物明细」表格的行。"""
    _title, _summary, content = build_finance_report(
        db_session, START, END, "测试区间", user_id=1
    )
    tables = [
        s for s in content
        if s.get("type") == "table" and s.get("header") == SHOPPING_HEADER
    ]
    assert tables, "报告中缺少购物明细表格"
    return tables[0]["rows"]


def test_platform_id_is_mapped_to_platform_name(db_session):
    """平台列输出平台名称，而不是内部 platform_id。"""
    db_session.add(FinanceShoppingPlatform(id=1, user_id=1, name="拼多多"))
    db_session.add(_record(1, "抽纸", 21.98, 1.05))
    db_session.flush()

    rows = _shopping_rows(db_session)
    assert rows[0][1] == "拼多多"
    assert rows[0][4] == "1.05"
    assert rows[0][5] == "21.98"


def test_missing_unit_price_outputs_blank_instead_of_zero(db_session):
    """源表 unit_price 为空时输出「—」，不能与总价自相矛盾地显示 0。"""
    db_session.add(FinanceShoppingPlatform(id=1, user_id=1, name="京东"))
    db_session.add(_record(1, "枕芯", 12.8, None))
    db_session.flush()

    rows = _shopping_rows(db_session)
    assert rows[0][1] == "京东"
    assert rows[0][4] == "—"
    assert rows[0][5] == "12.8"


def test_shopping_detail_rows_match_declared_total(db_session):
    """明细行数与摘要「购物 N 笔」、小节标题一致，不再截断成 30 行。"""
    for i in range(35):
        db_session.add(_record(None, f"商品{i:02d}", 10.0 + i, None))
    db_session.flush()

    _title, summary, content = build_finance_report(
        db_session, START, END, "测试区间", user_id=1
    )
    rows = _shopping_rows(db_session)
    assert len(rows) == 35
    assert "购物 35 笔" in summary
    heading = next(
        s["text"] for s in content
        if s.get("type") == "h2" and "购物明细" in s["text"]
    )
    assert heading == "四、购物明细（共 35 笔）"


def test_unknown_platform_falls_back_to_uncategorized(db_session):
    """平台未填写或平台已被删除时，平台列回落「未分类」而不是数字 id。"""
    db_session.add(_record(None, "耳塞", 11.0, 0.45))
    db_session.add(_record(99, "眼罩", 16.3, 0.2))
    db_session.flush()

    rows = _shopping_rows(db_session)
    assert [row[1] for row in rows] == ["未分类", "未分类"]
    assert all(row[4] != "0" for row in rows)
