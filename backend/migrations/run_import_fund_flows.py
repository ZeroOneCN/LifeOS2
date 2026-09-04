# -*- coding: utf-8 -*-
"""投资中心：覆盖导入 forex-capital-flows.csv 到 investment_fund_records。

映射规则（沿用现有 funds schema 三类型，不改后端）：
  deposit + is_bonus=FALSE -> deposit  入金(正)
  withdrawal             -> withdraw  出金(正)
  deposit + is_bonus=TRUE -> experience  体验金赠金入账(正)
  bonus_loss / bonus_expired -> experience  体验金亏损/失效(负)，汇总为体验金余额

运行：backend 目录 .venv\\Scripts\\python.exe migrations/run_import_fund_flows.py
"""
import csv
import os
import sys
from datetime import date, datetime

import pandas as pd
from sqlalchemy import text

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.database import Base, engine, SessionLocal
from app.models import InvestmentFundRecord

BACKUP_DIR = os.path.join(os.path.dirname(__file__), "..", "backups")
CSV = r"E:\Code\LifeOS V2.0\.trae\数据录取迁移\investment\forex-capital-flows.csv"


def parse_date(v):
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.strptime(v, fmt).date()
        except ValueError:
            continue
    return date.today()


def map_record(row) -> tuple[str, float]:
    """返回 (record_type, amount)。amount 演示金类为负时表示体验金减少。"""
    ftype = str(row["flow_type"]).strip().lower()
    is_bonus = str(row.get("is_bonus", "")).strip().upper() == "TRUE"
    amount = float(row["amount"])
    if ftype == "deposit":
        if is_bonus:
            return "experience", amount
        return "deposit", amount
    if ftype == "withdrawal":
        return "withdraw", amount
    if ftype in ("bonus_loss", "bonus_expired"):
        return "experience", -amount  # 体验金减少
    return "deposit", amount  # 兜底：未知归入金（不应出现）


def backup_insert(db, path):
    os.makedirs(BACKUP_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    bpath = os.path.join(BACKUP_DIR, f"investment_fund_records_{stamp}.csv")
    rows = db.execute(text("SELECT * FROM investment_fund_records")).mappings().all()
    if rows:
        cols = list(rows[0].keys())
        with open(bpath, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(cols)
            for r in rows:
                w.writerow([str(dict(r)[c]) for c in cols])
        print(f"  已备份现有 {len(rows)} 行 -> {bpath}")
    else:
        print("  现有表为空，跳过备份")


def main():
    Base.metadata.create_all(bind=engine)
    df = pd.read_csv(CSV, dtype=str).fillna("")
    print(f"读取 {len(df)} 行，字段: {list(df.columns)}")

    db = SessionLocal()
    try:
        user_id = db.execute(text("SELECT id FROM user_profile ORDER BY id LIMIT 1")).scalar()
        print(f"==> 归属用户 user_id = {user_id}")

        print("==> 备份现有 investment_fund_records")
        backup_insert(db, CSV)

        print("==> 清空并导入")
        # 覆盖：先清空该用户的资金记录
        db.query(InvestmentFundRecord).filter_by(user_id=user_id).delete()
        counter = 0
        skipped = 0
        for _, r in df.iterrows():
            if not str(r["flow_type"]).strip() or not str(r["amount"]).strip():
                skipped += 1
                continue
            rtype, amt = map_record(r)
            db.add(InvestmentFundRecord(
                user_id=user_id,
                record_type=rtype,
                amount=round(amt, 6),
                record_date=parse_date(r["flow_date"]),
                note=str(r["remark"]).strip() or None,
            ))
            counter += 1
        db.commit()
        print(f"  导入完成: {counter} 条 (跳过 {skipped})")
    finally:
        db.close()
    print("==> 完成")


if __name__ == "__main__":
    main()