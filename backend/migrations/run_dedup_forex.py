# -*- coding: utf-8 -*-
"""投资中心：清理 investment_forex 按 MT5 订单ID重复的记录。

备份 -> 对每个重复订单ID只保留最早一条(id最小)，删除多余重复 -> 校验到4140条。
运行：backend 目录 .venv\\Scripts\\python.exe migrations/run_dedup_forex.py
"""
import csv
import os
import sys
import re
from datetime import date, datetime
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text

from app.core.database import engine, SessionLocal

BACKUP_DIR = os.path.join(os.path.dirname(__file__), "..", "backups")


def note_id(note):
    if note:
        m = re.search(r"ID[:：]\s*([0-9]+)", str(note))
        if m:
            return m.group(1)
    return None


def backup(db):
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
        print(f"已备份全部 {len(rows)} 行 -> {bpath}")
    return bpath


def main():
    db = SessionLocal()
    try:
        print("==> 0) 备份")
        backup(db)

        print("==> 1) 统计重复")
        rows = db.execute(text("SELECT id, note FROM investment_forex")).fetchall()
        print("    当前总数:", len(rows))
        groups = defaultdict(list)
        no_id = []
        for (id_, note) in rows:
            n = note_id(note)
            if n:
                groups[n].append(id_)
            else:
                no_id.append(id_)
        dup_ids = [g for g in groups.values() if len(g) > 1]
        dup_count = sum(len(g) - 1 for g in dup_ids)
        print("    重复ID组:", len(dup_ids), " 多余条数:", dup_count, " 无ID记录(保留):", len(no_id))

        # 删除多余：每组保留 id 最小的
        delete_ids = []
        for g in dup_ids:
            g_sorted = sorted(g)
            delete_ids.extend(g_sorted[1:])
        print("==> 2) 删除重复多余", len(delete_ids), "条")

        # 分批删除
        BATCH = 500
        for i in range(0, len(delete_ids), BATCH):
            batch = delete_ids[i:i + BATCH]
            db.execute(text("DELETE FROM investment_forex WHERE id IN :ids"), {"ids": tuple(batch)})
            db.commit()
        print("    删除完成")

        after = db.execute(text("SELECT COUNT(*) FROM investment_forex")).scalar()
        print("==> 3) 清理后总数:", after)
    finally:
        db.close()


if __name__ == "__main__":
    main()