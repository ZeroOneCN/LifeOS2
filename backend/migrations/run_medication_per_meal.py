"""medication 表结构调整迁移：同一药品同一天合并为一行（早/午/晚分餐剂量）。

- health_medication: 由 meal_slot+dosage+taken 改为 dose_breakfast/lunch/dinner + taken_* 每餐独立字段
- health_med_purchase: 新增 pills_per_unit（每盒/瓶粒数）
执行前自动备份两张表数据到 migrations/backup/
"""
import os
from collections import OrderedDict
from datetime import datetime

import pymysql

HOST, USER, PWD, DB = "127.0.0.1", "root", "123456", "lifeos"
MIGS = os.path.dirname(os.path.abspath(__file__))
BACKUP = os.path.join(MIGS, "backup")
os.makedirs(BACKUP, exist_ok=True)

db = pymysql.connect(host=HOST, user=USER, password=PWD, database=DB, charset="utf8mb4")
cur = db.cursor()

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")


def dump_table(name: str) -> None:
    cur.execute(f"SELECT * FROM {name}")
    cols = [d[0] for d in cur.description]
    path = os.path.join(BACKUP, f"{name}_{stamp}.tsv")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(cols) + "\n")
        for row in cur.fetchall():
            f.write("\t".join("" if v is None else str(v) for v in row) + "\n")
    print(f"backed up {name} -> {path} ({len(open(path).readlines())-1} rows)")


def table_exists(name: str) -> bool:
    cur.execute("SHOW TABLES LIKE %s", (name,))
    return cur.fetchone() is not None


# ---- 1. 备份 ----
for t in ("health_medication", "health_med_purchase", "health_med_stock"):
    if table_exists(t):
        dump_table(t)

# ---- 2. 读取旧用药数据，合并为按天一行 ----
cur.execute(
    "SELECT id, record_date, medicine_name, meal_slot, dosage, taken, user_id, note, frequency, "
    "created_at, updated_at "
    "FROM health_medication ORDER BY record_date, medicine_name, id"
)
grouped: "OrderedDict[tuple, dict]" = OrderedDict()
for rid, rdate, mname, meal, dosage, taken, uid, note, freq, created, updated in cur.fetchall():
    try:
        dose = int(float(dosage))
    except (TypeError, ValueError):
        dose = 0
    key = (rdate, mname)
    g = grouped.setdefault(
        key,
        {
            "record_date": rdate,
            "medicine_name": mname,
            "user_id": uid,
            "note": note,
            "frequency": freq,
            "created_at": created,
            "updated_at": updated,
            "d": {"breakfast": 0, "lunch": 0, "dinner": 0},
            "t": {"breakfast": 0, "lunch": 0, "dinner": 0},
            "first_id": rid,
        },
    )
    g["d"][meal] = max(g["d"][meal], dose)
    g["t"][meal] = 1 if taken else 0

# ---- 3. 重建 health_medication（合并后单行） ----
cur.execute("DROP TABLE IF EXISTS health_medication_new")
cur.execute(
    """
    CREATE TABLE health_medication_new (
      id INT AUTO_INCREMENT PRIMARY KEY,
      record_date DATE NOT NULL,
      medicine_name VARCHAR(64) NOT NULL,
      dose_breakfast INT NOT NULL DEFAULT 0,
      dose_lunch INT NOT NULL DEFAULT 0,
      dose_dinner INT NOT NULL DEFAULT 0,
      taken_breakfast TINYINT(1) NOT NULL DEFAULT 0,
      taken_lunch TINYINT(1) NOT NULL DEFAULT 0,
      taken_dinner TINYINT(1) NOT NULL DEFAULT 0,
      frequency VARCHAR(64),
      note TEXT,
      created_at DATETIME,
      updated_at DATETIME,
      user_id INT,
      INDEX ix_record_date (record_date),
      INDEX ix_medicine_name (medicine_name),
      INDEX ix_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """
)
for key, g in grouped.items():
    cur.execute(
        "INSERT INTO health_medication_new (record_date, medicine_name, dose_breakfast, dose_lunch, "
        "dose_dinner, taken_breakfast, taken_lunch, taken_dinner, frequency, note, created_at, updated_at, user_id) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (
            g["record_date"],
            g["medicine_name"],
            g["d"]["breakfast"],
            g["d"]["lunch"],
            g["d"]["dinner"],
            g["t"]["breakfast"],
            g["t"]["lunch"],
            g["t"]["dinner"],
            g["frequency"],
            g["note"],
            g["created_at"],
            g["updated_at"],
            g["user_id"],
        ),
    )
db.commit()
print(f"merged health_medication: {len(grouped)} rows")

cur.execute("DROP TABLE health_medication")
cur.execute("RENAME TABLE health_medication_new TO health_medication")
db.commit()

# ---- 4. health_med_purchase 新增 pills_per_unit ----
cur.execute("SHOW COLUMNS FROM health_med_purchase")
cols = {r[0] for r in cur.fetchall()}
if "pills_per_unit" not in cols:
    cur.execute("ALTER TABLE health_med_purchase ADD COLUMN pills_per_unit FLOAT NULL AFTER quantity")
    db.commit()
    print("added pills_per_unit to health_med_purchase")

# ---- 5. 清理 ----
os.path.join(BACKUP, stamp)  # keep stamp reference
db.close()
print("done")