"""药品按粒库存计算测试：无购药、消耗超购入、每单位粒数为空与日均预测。"""

from datetime import date, timedelta

from app.models import HealthMedication, HealthMedPurchase, HealthMedStock
from app.services.med_stock import compute_med_stock_list


def _add_purchase(db, user_id: int, name: str, quantity: float, pills_per_unit, buy_date=None):
    """插入一条购药记录，返回该 ORM 对象。"""
    row = HealthMedPurchase(
        user_id=user_id,
        buy_date=buy_date or date.today(),
        medicine_name=name,
        quantity=quantity,
        pills_per_unit=pills_per_unit,
        unit_price=1.0,
    )
    db.add(row)
    db.flush()
    return row


def _add_med(db, user_id: int, name: str, day: date, dose: int = 2, taken: bool = True):
    """插入一条用药记录（默认早餐+午餐各 1 粒且已服）。"""
    row = HealthMedication(
        user_id=user_id,
        record_date=day,
        medicine_name=name,
        dose_breakfast=1,
        dose_lunch=dose - 1,
        taken_breakfast=taken,
        taken_lunch=taken,
    )
    db.add(row)
    db.flush()
    return row


def test_stock_without_purchase_or_consumption(db_session):
    """无购药、无用药时库存为 0，且不产生日均消耗预测。"""
    db_session.add(
        HealthMedStock(user_id=1, medicine_name="维生素C", stock_qty=0, threshold=5)
    )
    db_session.flush()
    rows = compute_med_stock_list(db_session, 1)
    assert len(rows) == 1
    row = rows[0]
    assert row["stock_qty"] == 0
    assert row["purchased"] == 0
    assert row["consumed"] == 0
    assert row["avg_daily"] is None
    assert row["days_left"] is None
    assert row["predicted_date"] is None
    assert row["is_low"] is True  # 0 <= 阈值 5


def test_consumption_exceeding_purchase_clamps_to_zero(db_session):
    """消耗超过购入时库存夹紧为 0，不出现负数。"""
    db_session.add(HealthMedStock(user_id=1, medicine_name="布洛芬", stock_qty=0))
    _add_purchase(db_session, 1, "布洛芬", quantity=2, pills_per_unit=10)  # 20 粒
    today = date.today()
    for offset in range(3):
        _add_med(db_session, 1, "布洛芬", today - timedelta(days=offset), dose=10)
    rows = compute_med_stock_list(db_session, 1)
    row = rows[0]
    assert row["purchased"] == 20
    assert row["consumed"] == 30
    assert row["stock_qty"] == 0
    assert row["days_left"] is None  # 库存为 0 时不预测


def test_pills_per_unit_none_falls_back_to_one(db_session):
    """pills_per_unit 为空时按 1 粒/单位计算，避免 None 参与乘法报错。"""
    db_session.add(HealthMedStock(user_id=1, medicine_name="钙片", stock_qty=0))
    _add_purchase(db_session, 1, "钙片", quantity=5, pills_per_unit=None)
    rows = compute_med_stock_list(db_session, 1)
    assert rows[0]["purchased"] == 5
    assert rows[0]["stock_qty"] == 5


def test_avg_daily_and_predicted_date(db_session):
    """日均消耗按最近用药跨度计算，耗尽日期 = 今天 + 剩余天数。"""
    db_session.add(HealthMedStock(user_id=1, medicine_name="阿司匹林", stock_qty=0))
    _add_purchase(db_session, 1, "阿司匹林", quantity=10, pills_per_unit=1)  # 10 粒
    today = date.today()
    for offset in range(4):  # 今天及前 3 天，每天 2 粒 -> 共 8 粒，跨度 4 天
        _add_med(db_session, 1, "阿司匹林", today - timedelta(days=offset), dose=2)
    rows = compute_med_stock_list(db_session, 1)
    row = rows[0]
    assert row["consumed"] == 8
    assert row["stock_qty"] == 2
    assert row["avg_daily"] == 2.0
    assert row["days_left"] == 1
    assert row["predicted_date"] == (today + timedelta(days=1)).isoformat()


def test_threshold_none_never_low(db_session):
    """阈值为空时永不算低库存。"""
    db_session.add(
        HealthMedStock(user_id=1, medicine_name="眼药水", stock_qty=1, threshold=None)
    )
    db_session.flush()
    assert compute_med_stock_list(db_session, 1)[0]["is_low"] is False


def test_user_isolation(db_session):
    """只统计当前用户的库存、购药与用药记录。"""
    db_session.add(HealthMedStock(user_id=1, medicine_name="药品A", stock_qty=0))
    db_session.add(HealthMedStock(user_id=2, medicine_name="药品B", stock_qty=0))
    _add_purchase(db_session, 2, "药品A", quantity=99, pills_per_unit=1)
    _add_med(db_session, 2, "药品A", date.today(), dose=5)
    rows = compute_med_stock_list(db_session, 1)
    assert [r["medicine_name"] for r in rows] == ["药品A"]
    assert rows[0]["purchased"] == 0
    assert rows[0]["consumed"] == 0
