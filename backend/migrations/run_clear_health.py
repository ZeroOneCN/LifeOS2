"""清空健康模块数据：备份后逐表清空（含自增重置）。

涉及表：medication / med_purchase / med_stock / steps / fitness / body / vitals_sleep / checkup / diet
说明：保留 health 下模板/组合/报告等参考类数据不动。
"""
import os
from datetime import datetime

import pymysql

HOST, USER, PWD, DB = "127.0.0.1", "root", "123456", "lifeos"
MIGS = os.path.dirname(os.path.abspath(__file__))
BACKUP = os.path.join(MIGS, "backup")
os.makedirs(BACKUP, exist_ok=True)
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

TABLES = [
    "health_medication",
    "health_med_purchase",
    "health_med_stock",
    "health_steps",
    "health_fitness",
    "health_body",
    "health_vitals_sleep",
    "health_checkup",
    "health_diet",
]

db = pymysql.connect(host=HOST, user=USER, password=PWD, database=DB, charset="utf8mb4")
cur = db.cursor()


def dump_table(name: str) -> int:
    cur.execute(f"SELECT * FROM {name}")
    rows = cur.fetchall()
    if not rows:
        return 0
    path = os.path.join(BACKUP, f"health_clear_{name}_{stamp}.tsv")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(d[0] for d in cur.description) + "\n")
        for row in rows:
            f.write("\t".join("" if v is None else str(v) for v in row) + "\n")
    return len(rows)


total = 0
for t in TABLES:
    n = dump_table(t)
    cur.execute(f"TRUNCATE TABLE {t}")
    total += n
    print(f"cleared {t}: {n} rows")
db.commit()
db.close()
print(f"TOTAL cleared: {total} rows")