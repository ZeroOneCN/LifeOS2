# -*- coding: utf-8 -*-
"""投资中心：覆盖导入 forex-trade-records.csv 到 investment_forex。

流程：备份现有数据 -> 清空 investment_forex -> 导入 4140 条。
依赖 neighbor 脚本复用文件读取工具。
运行：backend 目录 .venv\\Scripts\\python.exe migrations/run_import_forex_trades.py
"""
import csv
import os
import sys
from datetime import datetime, date, time, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pandas as pd
from sqlalchemy import text

from app.core.database import Base, engine, SessionLocal
from app.models import InvestmentForex

BACKUP_DIR = os.path.join(os.path.dirname(__file__), "..", "backups")
CSV = r"E:\Code\LifeOS V2.0\.trae\数据录取迁移\investment\forex-trade-records.csv"


def parse_date(v):
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.strptime(v, fmt).date()
        except ValueError:
            continue
    return date.today()


def parse_time_str(v):
    if not v or str(v).strip() == "":
        return None
    s = str(v).strip()
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(s, fmt).time()
        except ValueError:
            continue
    return None


def combine(day, t_str):
    t = parse_time_str(t_str)
    if t is None:
        return None
    return datetime.combine(day, t)


def hold_to_minutes(hold_time):
    """hold_time 形如 0:02:37 或 '1天 16:30:00' -> 分钟。"""
    if not hold_time or str(hold_time).strip() == "":
        return None
    s = str(hold_time).strip()
    # 处理 "N天 H:M:S"
    days = 0
    if "天" in s:
        left, s = s.split("天", 1)
        try:
            days = int(left)
        except ValueError:
            days = 0
    parts = [int(x) for x in s.strip().split(":") if x.strip()]
    if not parts:
        return days * 24 * 60 if days else None
    hms_minutes = 0
    if len(parts) == 3:
        hms_minutes = parts[0] * 60 + parts[1] + round(parts[2] / 60)
    elif len(parts) == 2:
        hms_minutes = parts[0] * 60 + parts[1]
    else:
        hms_minutes = parts[0]
    return days * 24 * 60 + hms_minutes


def backup_insert(db, path):
    os.makedirs(BACKUP_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    bpath = os.path.join(BACKUP_DIR, f"investment_forex_{stamp}.csv")
    rows = db.execute(text("SELECT * FROM investment_forex")).mappings().all()
    if rows:
        cols = list(rows[0].keys())
        with open(bpath, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            for r in rows:
                w.writerow({k: (v.isoformat() if isinstance(v, (date, datetime)) else v) for k, v in dict(r).items()})
        print(f"  已备份现有 {len(rows)} 行 -> {bpath}")
    else:
        print("  现有表为空，跳过备份")


def main():
    Base.metadata.create_all(bind=engine)
    df = pd.read_csv(CSV, dtype=str)
    df = df.fillna("")
    print(f"读取 {len(df)} 行，字段: {list(df.columns)}")

    db = SessionLocal()
    try:
        # 归属当前登录用户（UserOwned.user_id 非空）
        user_id = db.execute(text("SELECT id FROM user_profile ORDER BY id LIMIT 1")).scalar()
        print(f"==> 归属用户 user_id = {user_id}")

        print("==> 0) 备份现有 investment_forex")
        backup_insert(db, CSV)

        print("==> 1) 清空 investment_forex")
        db.query(InvestmentForex).delete()

        print("==> 2) 逐行导入")
        counter = 0
        skipped = 0
        for _, r in df.iterrows():
            day = parse_date(r["trade_date"])
            open_dt = combine(day, r["open_time"])
            close_dt = combine(day, r["close_time"])
            # 跨日：平仓时间早于开仓时间时，+1 天
            if close_dt and open_dt and close_dt < open_dt:
                close_dt = close_dt + timedelta(days=1)
            note = r["remark"].strip() or None
            db.add(InvestmentForex(
                user_id=user_id,
                trade_date=day,
                symbol=r["instrument"].strip(),
                order_type=r["order_type"].strip().lower(),
                open_price=float(r["open_price"]),
                lot_size=float(r["lot_size"]),
                commission=float(r["commission"]),
                close_price=float(r["close_price"]),
                pnl=float(r["pnl"]),
                overnight_fee=float(r["overnight_fee"]),
                open_time=open_dt,
                close_time=close_dt,
                holding=hold_to_minutes(r["hold_time"]),
                status="closed",
                note=note,
            ))
            counter += 1
        db.commit()
        print(f"  导入完成: {counter} 条 (跳过 {skipped})")
    finally:
        db.close()
    print("==> 完成")


if __name__ == "__main__":
    main()