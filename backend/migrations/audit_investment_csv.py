# -*- coding: utf-8 -*-
"""深度校验：分离可导入与不可导入的行(不写库)。"""
import pandas as pd
import os

DIR = r"E:\Code\LifeOS V2.0\.trae\数据录取迁移\investment"

# ---- 1) trade-records 深度校验 ----
td = pd.read_csv(os.path.join(DIR, "forex-trade-records.csv"), dtype=str).fillna("")
issues = {}
issues["order_type非法"] = int((~td["order_type"].isin(["buy", "sell"])).sum())
issues["trade_date缺失"] = int((td["trade_date"] == "").sum())
# instrument 均非空
issues["instrument缺失"] = int((td["instrument"] == "").sum())
# 开仓价/手数 数值校验
num_ok = pd.to_numeric(td["open_price"], errors="coerce")
issues["open_price非法"] = int(num_ok.isna().sum())
issues["lot_size非法"] = int(pd.to_numeric(td["lot_size"], errors="coerce").isna().sum())
# position_id 重复
issues["position_id重复"] = int(td["position_id"].duplicated().sum())
# remark 里有"|"分隔的 TP/SL 信息，note 字段可完整存下，非阻断
print("=" * 60)
print("[trade-records] 可映射字段齐全。潜在问题：")
for k, v in issues.items():
    print(f"  {k}: {v}")
print(f"  remove中的' | '备注样例行数: {int(td['remark'].str.contains('\\|').sum())} (可作为备注保留)")

# ---- 2) capital-flows 分离 ----
cf = pd.read_csv(os.path.join(DIR, "forex-capital-flows.csv"), dtype=str).fillna("")
mappable = {"deposit": "deposit", "withdrawal": "withdraw"}
cf["mapped_type"] = cf["flow_type"].map(mappable)
ok = cf[cf["mapped_type"].notna()]
bad = cf[cf["mapped_type"].isna()]
print("=" * 60)
print(f"[capital-flows] 总 {len(cf)} 行")
print(f"  可导入 (deposit/withdrawal -> deposit/withdraw): {len(ok)} 行")
print(f"  不可导入: {len(bad)} 行  —— 类型: {dict(bad['flow_type'].value_counts())}")
print("  不可导入的具体行：")
print(bad[["flow_date", "flow_type", "amount", "is_bonus"]].to_string(index=False))
print(f"  is_bonus=TRUE 的行({int((cf['is_bonus']=='TRUE').sum())})：现有 funds 无 is_bonus 列，将并入 remark 备注")

# ---- 3) setting ----
print("=" * 60)
print("[forex-setting] 账户参数(杠杆/爆仓比/看板日期) — 后端无对应持久化表，无法导入")
print("  说明：仓位计算为前端实时计算，不涉及落库")