# 金额列 Float/Double → Numeric(12,2) 迁移调研

> 调研时间：2026-11-07　数据库：MySQL 8.0.44（127.0.0.1:3307 / lifeos2，InnoDB，STRICT_TRANS_TABLES）
> 性质：**只读调研**。全程未执行任何 `ALTER`、未修改任何 `.py`、未写入数据库；所有数据来自 `information_schema` 与只读 `SELECT`。

---

## 0. 结论（一眼判断）

| 问题 | 结论 |
|---|---|
| **现在是否做全量金额列迁移？** | **不做（No-Go for now）** |
| 为什么 | ① 数据层几乎没有收益：44 个金额列中**只有 1 行**超过 2 位小数（`finance_repayments` id=294 = `6.739999999999999`），全部金额表的合计与「先 ROUND 到分再加总」的差异总计仅 **0.0033 元**；② 代码层有 **13 个文件、16 处 P0** `Decimal` 与 `float` 混算点，改完 ORM 当天就会 500，需要同步返工并补回归测试；③ 收益是「长期防漂移」，不是修现有错账。 |
| 那先做什么 | **Phase 0**：把 1 行脏值修为 `6.74`；**Phase 1**：只改代码（Decimal 安全累加器 + 边界 `float()`），**不动库**，可独立发布；**Phase 2**：汇率/费率列单独定精度（`rate_to_cny`、`penalty_rate`、`interest_rate`、外汇开平仓价）；**Phase 3**（下一轮）：44 个金额列 `ALTER` 到 `DECIMAL(12,2)`。 |
| 如果坚持本轮就迁 | 必须与 Phase 1 的 16 处 P0 代码修复**同一批次**上线，且先补「聚合接口」回归测试；否则 `/finance/overview`、财务/投资报告、手机卡余额、购物/旅行统计会直接 500（详见第 3 节）。 |

---

## 1. 盘点

### 1.1 统计口径

- 数据库共命中 **99 个** `FLOAT/DOUBLE` 列（33 张表），**0 个**现存 `DECIMAL/NUMERIC` 列。
- 按用途分三类：
  - **A. 金额类（44 列）**：应以「分」为最小单位，候选 `DECIMAL(12,2)`。
  - **B. 比率/价格类（6 列）**：不能一律 2 位（汇率、日费率、年利率、外汇报价、手数），单独定精度。
  - **C. 非财务计量类（49 列）**：身高体重、体脂、血压血氧、热量、步幅、步数距离、检验值、药品粒数等，**不参与本次迁移**。
- **索引/唯一约束/外键**：99 列**全部没有**被索引、没有进入任何唯一约束、也没有被任何外键引用（`COLUMN_KEY`/`STATISTICS`/`KEY_COLUMN_USAGE` 三处交叉核对）。因此改类型不会触发索引/约束重建。
- 最大绝对值：金额列 **200,000**（`finance_planning.target_amount`），远低于 `DECIMAL(12,2)` 上限 `9,999,999,999.99`，无溢出风险。

### 1.2 A 类：金额列（44 列，候选 `DECIMAL(12,2)`）

| # | 表.列 | 现库类型 | 可空 / 默认 | 行数 / 非空 | 小数位分布（行数） | >2 位行数 | 索引/唯一/外键 |
|---|---|---|---|---|---|---|---|
| 1 | finance_debt_payments.amount | float | NOT NULL / — | 10 / 10 | 0:6, 2:4 | 0 | 无 |
| 2 | finance_debt_payments.discount | float | NULL / 0 | 10 / 10 | 0:7, 1:1, 2:2 | 0 | 无 |
| 3 | finance_debts.amount | float | NOT NULL / — | 26 / 26 | 0:25, 2:1 | 0 | 无 |
| 4 | finance_debts.remaining | float | NULL / — | 26 / 19 | 0:16, 1:2, 2:1 | 0 | 无 |
| 5 | finance_debts.interest_total | float | NULL / — | 26 / 26 | 0:24, 2:2 | 0 | 无 |
| 6 | finance_housing.actual_monthly_rent | float | NOT NULL / — | 11 / 11 | 0:8, 2:3 | 0 | 无 |
| 7 | finance_housing.deposit | float | NULL / — | 11 / 11 | 0:11 | 0 | 无 |
| 8 | finance_housing.agent_fee | float | NULL / — | 11 / 11 | 0:11 | 0 | 无 |
| 9 | finance_housing.clean_fee | float | NULL / — | 11 / 11 | 0:11 | 0 | 无 |
| 10 | finance_housing.service_fee | float | NULL / — | 11 / 11 | 0:9, 1:1, 2:1 | 0 | 无 |
| 11 | finance_housing.laundry_fee | float | NULL / — | 11 / 11 | 0:10, 2:1 | 0 | 无 |
| 12 | finance_housing.deposit_refunded | float | NULL / 0 | 11 / 11 | 0:11 | 0 | 无 |
| 13 | finance_investments.pnl | float | NOT NULL / — | 13 / 13 | 0:1, 1:1, 2:11 | 0 | 无 |
| 14 | finance_loan_bills.amount | **double** | NOT NULL / — | 347 / 347 | 0:31, 1:36, 2:280 | 0 | 无 |
| 15 | finance_loan_bills.interest | **double** | NULL / 0 | 347 / 345 | 0:244, 1:1, 2:100 | 0 | 无 |
| 16 | finance_loan_bills.paid_amount | **double** | NOT NULL / 0 | 347 / 347 | 0:104, 1:32, 2:211 | 0 | 无 |
| 17 | finance_loan_platforms.credit_limit | float | NULL / — | 10 / 10 | 0:10 | 0 | 无 |
| 18 | finance_planning.target_amount | float | NULL / — | 1 / 1 | 0:1 | 0 | 无 |
| 19 | finance_planning.saved_amount | float | NULL / — | 1 / 1 | 0:1 | 0 | 无 |
| 20 | finance_rent_terms.amount | float | **NULL / 0**（模型声明非空，见 1.5） | 19 / 19 | 0:10, 2:9 | 0 | 无 |
| 21 | finance_repayments.amount | **double** | NOT NULL / — | 299 / 299 | 0:34, 1:32, 2:232, **>8:1** | **1** | 无 |
| 22 | finance_repayments.discount | **double** | NULL / 0 | 299 / 299 | 0:290, 2:9 | 0 | 无 |
| 23 | finance_shopping_records.total_price | float | NOT NULL / — | 426 / 426 | 0:18, 1:147, 2:261 | 0 | 无 |
| 24 | finance_shopping_records.unit_price | float | NULL / — | 426 / 55 | 0:1, 1:6, 2:48 | 0 | 无 |
| 25 | finance_subscriptions.amount | float | NOT NULL / — | 2 / 2 | 0:1, 2:1 | 0 | 无 |
| 26 | finance_travel_details.original_price | float | NOT NULL / — | 50 / 50 | 0:39, 1:4, 2:7 | 0 | 无 |
| 27 | finance_travel_details.discount | float | NOT NULL / — | 50 / 50 | 0:36, 1:4, 2:10 | 0 | 无 |
| 28 | finance_travel_details.actual_price | float | NOT NULL / — | 50 / 50 | 0:29, 1:4, 2:17 | 0 | 无 |
| 29 | finance_utilities.amount | float | NOT NULL / — | 47 / 47 | 0:3, 1:12, 2:32 | 0 | 无 |
| 30 | investment_forex.pnl | float | NULL / — | 4,277 / 4,277 | 0:66, 1:521, 2:3,690 | 0 | 无 |
| 31 | investment_forex.commission | float | NOT NULL / 0 | 4,277 / 4,277 | 0:2,686, 1:157, 2:1,434 | 0 | 无 |
| 32 | investment_forex.overnight_fee | float | NOT NULL / 0 | 4,277 / 4,277 | 0:4,274, 2:3 | 0 | 无 |
| 33 | investment_fund_records.amount | float | NOT NULL / — | 70 / 70 | 0:17, 1:7, 2:46 | 0 | 无 |
| 34 | lifestyle_bank_cards.balance | float | NULL / 0 | 20 / 20 | 0:20 | 0 | 无 |
| 35 | lifestyle_bank_cards.credit_limit | float | NULL / 0 | 20 / 20 | 0:20 | 0 | 无 |
| 36 | lifestyle_card_bills.amount | float | NOT NULL / — | 17 / 17 | 0:17 | 0 | 无 |
| 37 | lifestyle_items.price | float | NULL / — | 426 / 426 | 0:18, 1:147, 2:261 | 0 | 无 |
| 38 | lifestyle_phone_cards.balance | float | NULL / 0 | 9 / 9 | 0:4, 1:3, 2:2 | 0 | 无 |
| 39 | lifestyle_phone_cards.monthly_fee | float | NULL / 0 | 9 / 9 | 0:9 | 0 | 无 |
| 40 | lifestyle_phone_cards.opening_balance | float | NOT NULL / 0 | 9 / 9 | 0:3, 1:2, 2:4 | 0 | 无 |
| 41 | lifestyle_phone_ledgers.amount | float | NOT NULL / — | 35 / 35 | 0:31, 1:2, 2:2 | 0 | 无 |
| 42 | lifestyle_phone_recharges.amount | float | NOT NULL / — | 17 / 17 | 0:13, 1:2, 2:2 | 0 | 无 |
| 43 | health_med_purchase.unit_price | float | NOT NULL / — | 24 / 24 | 0:5, 1:4, 2:15 | 0 | 无 |
| 44 | health_med_purchase.total_price | float | NULL / — | 24 / 24 | 0:4, 1:12, 2:8 | 0 | 无 |

> 注：`finance_planning` 实际 1 行（`information_schema.TABLE_ROWS` 是估算值，正文一律用真实 `COUNT(*)`）。
> `lifestyle_items.price` 与 `finance_shopping_records.total_price` 行数/分布完全一致，来自购物同步，金额合计均为 8,492.08。

### 1.3 B 类：比率 / 价格列（6 列，**不要一律用 2 位**）

| 表.列 | 现库类型 | 行数 / 非空 | 实际取值 | 建议类型 | 理由 |
|---|---|---|---|---|---|
| finance_currencies.rate_to_cny | float | 3 / 3 | CNY `1`、USD `7`、HKD `0.9` | `DECIMAL(12,6)` | 汇率；2 位会存成 `0.90`/`7.00`（值不变），但未来 `7.1234` 会被截断 |
| finance_loan_platforms.penalty_rate | double | 10 / 10 | 0.05（%/天）×9、5（%/天）×1 | `DECIMAL(6,4)` | 日费率，0.05% 必须保住 2 位有效小数；2 位也能存，但留给更细费率 |
| finance_debts.interest_rate | float | 26 / **0（全 NULL）** | — | `DECIMAL(6,4)` | 年利率 %，可能 3.65、4.125 |
| investment_forex.open_price | float | 4,277 / 4,277 | 最大 4,703.5698（FLOAT 存储 4703.56982421875）；**14 行 3 位小数** | `DECIMAL(12,4)` | 外汇报价，2 位会改价（如 `79.017`→`79.02`，id=6057） |
| investment_forex.close_price | float | 4,277 / 4,277 | 最大 4,702.0601（FLOAT 存储 4702.06005859375）；**17 行 3 位小数** | `DECIMAL(12,4)` | 同上（如 `78.936`） |
| investment_forex.lot_size | float | 4,277 / 4,277 | 0.01 / 0.1 / 0.3 | `DECIMAL(10,2)` | 手数，2 位够；但它是数量，不是金额 |

### 1.4 C 类：非财务计量 Float（49 列，**本次不动**）

- `health_body` 23 列（BMI、体脂率、肌肉/水分/骨量等）
- `health_checkup` 3 列 + `health_checkup_panel_item` 2 列 + `health_checkup_template` 2 列（检验值、参考上下限）
- `health_vitals_sleep` 4 列（血氧、血糖、体温、平均心率）
- `health_diet` 5 列（克数、热量、蛋白/碳水/脂肪）
- `health_fitness` 2 列（热量、距离）
- `health_steps` 3 列（步幅、距离、热量）+ `health_step_setting.stride_cm` 1 列
- `health_med_purchase.quantity` / `pills_per_unit` 2 列 + `health_med_stock` 2 列（现有量、阈值）

这些是**测量值**，不是金额；若迁 `Numeric` 应按量纲定 1~3 位，且会牵动体脂秤/报告计算，建议本轮完全排除。

### 1.5 模型与库不一致（迁移前需先澄清，避免 Alembic 误判）

| 位置 | 模型声明 | 实际库 | 影响 |
|---|---|---|---|
| `backend/app/models/finance.py#L250-L252`（FinanceLoanBill） | `Float` | **double** | 迁移时 `existing_type` 必须是 `sa.Double()`，否则 autogenerate 会生成无关 diff |
| `backend/app/models/finance.py#L267-L268`（FinanceRepayment） | `Double` | double | 一致 |
| `backend/app/models/finance.py#L174`（FinanceRentTerm.amount） | `Mapped[float]`（非空） | **NULL + 默认 0** | 迁移时若照模型改 NOT NULL，属于行为变更；建议先保持库现状 |
| `backend/alembic/versions/943429348ec7_baseline_...py` | 金额列几乎全写 `sa.Float()`，仅 `finance_repayments` 写 `sa.Double()` | `finance_loan_bills` 3 列与 `finance_repayments` 2 列均为 double | 基线与现网漂移（`finance_loan_bills`：`Float` → `double`）；新迁移必须显式写 `existing_type` |
| `health_med_stock` 等 | `Float` | float | 一致 |

---

## 2. 现网数据体检

### 2.1 总体结论

- **金额类 44 列**合计：迁移前 `SUM(col)` 与迁移后 `SUM(ROUND(col,2))` 的差异总计 **≈0.0033 元**；单行最大偏差 **0.000781 元**（`finance_debts.remaining`，FLOAT 4 字节精度导致）。
- **超过 2 位小数的金额行：全库仅 1 行**（`finance_repayments` id=294，`6.739999999999999`）。
- 比率/价格类中，外汇开/平仓价各有 **14 / 17 行 3 位小数**，**不属于金额**，迁移时必须单独定 4 位精度，否则会真实改价。
- 44 个金额列按 `CAST(col AS CHAR)` 检查，**科学计数法脏值 0 行**；`interest_rate` 全 NULL 已在 B 类单独列出。

### 2.2 逐列「合计 / 四舍五入后合计 / 最大单行偏差」

| 表.列 | SUM(原值) | SUM(ROUND(…,2)) | 最大单行偏差 | 说明 |
|---|---|---|---|---|
| finance_debt_payments.amount | 1,364.269999 | 1,364.27 | 0.000002 | FLOAT 精度噪声 |
| finance_debt_payments.discount | 48.959998 | 48.96 | 0.000002 | 同上 |
| finance_debts.amount | **213,094.429688** | **213,094.43** | 0.000313 | 典型 FLOAT 累加漂移 |
| finance_debts.remaining | **179,708.259766** | **179,708.26** | **0.000781** | 全库最大单行偏差 |
| finance_debts.interest_total | 200.240005 | 200.24 | 0.000007 | — |
| finance_housing.actual_monthly_rent | 9,933.609940 | 9,933.61 | 0.000044 | — |
| finance_housing.deposit | 7,168.00 | 7,168.00 | 0 | 精确 |
| finance_housing.agent_fee | 640.00 | 640.00 | 0 | 精确 |
| finance_housing.clean_fee | 35.00 | 35.00 | 0 | 精确 |
| finance_housing.service_fee | 753.440002 | 753.44 | 0.000006 | — |
| finance_housing.laundry_fee | 48.34 | 48.34 | 0 | 精确 |
| finance_housing.deposit_refunded | 6,187.00 | 6,187.00 | 0 | 精确 |
| finance_investments.pnl | -6,229.490052 | -6,229.49 | 0.000054 | — |
| finance_loan_bills.amount | 701,027.64 | 701,027.64 | 0 | DOUBLE，精确到分 |
| finance_loan_bills.interest | 11,245.54 | 11,245.54 | 0 | — |
| finance_loan_bills.paid_amount | 652,207.31 | 652,207.31 | 0 | 与还款明细勾稽一致 |
| finance_loan_platforms.credit_limit | 65,200.00 | 65,200.00 | 0 | — |
| finance_planning.target_amount | 200,000.00 | 200,000.00 | 0 | — |
| finance_planning.saved_amount | 0 | 0 | 0 | — |
| finance_rent_terms.amount | 23,552.450172 | 23,552.45 | 0.000107 | — |
| finance_repayments.amount | 652,195.71 | 652,195.71 | 0（展示精度） | 含 1 行 `6.739999999999999` |
| finance_repayments.discount | 11.60 | 11.60 | 0 | — |
| finance_shopping_records.total_price | 8,492.079986 | 8,492.08 | 0.000005 | — |
| finance_shopping_records.unit_price | 111.46 | 111.46 | 0 | — |
| finance_subscriptions.amount | 295.109985 | 295.11 | 0.000015 | — |
| finance_travel_details.original_price | 2,805.890013 | 2,805.89 | 0.000011 | — |
| finance_travel_details.discount | 239.03 | 239.03 | 0 | — |
| finance_travel_details.actual_price | 2,566.860011 | 2,566.86 | 0.000011 | 原价-优惠勾稽一致 |
| finance_utilities.amount | 3,448.209990 | 3,448.21 | 0.000006 | — |
| investment_forex.pnl | -2,599.039993 | -2,599.04 | 0.000004 | — |
| investment_forex.commission | -175.320001 | -175.32 | 0 | — |
| investment_forex.overnight_fee | -2.37 | -2.37 | 0 | — |
| investment_fund_records.amount | 9,206.160073 | 9,206.16 | 0.000054 | — |
| lifestyle_bank_cards.balance / credit_limit | 0 / 0 | 0 / 0 | 0 | 全 0 |
| lifestyle_card_bills.amount | 306.00 | 306.00 | 0 | — |
| lifestyle_items.price | 8,492.079986 | 8,492.08 | 0.000005 | 与购物同步 |
| lifestyle_phone_cards.balance | 119.759998 | 119.76 | 0.000001 | — |
| lifestyle_phone_cards.monthly_fee | 153.00 | 153.00 | 0 | — |
| lifestyle_phone_cards.opening_balance | 60.360001 | 60.36 | 0.000001 | — |
| lifestyle_phone_ledgers.amount | 59.40 | 59.40 | 0.000001 | 含正负号 |
| lifestyle_phone_recharges.amount | 337.40 | 337.40 | 0.000001 | — |
| health_med_purchase.unit_price | 418.609991 | 418.61 | 0.000001 | — |
| health_med_purchase.total_price | 710.199986 | 710.20 | 0.000002 | — |

### 2.3 唯一超过 2 位小数的金额行（迁移会「改值」的唯一记录）

```sql
-- 只读定位（MySQL 8）
SELECT id, bill_id, repay_date, amount, CAST(amount AS CHAR) AS amount_text,
       discount, method, note, created_at
FROM finance_repayments
WHERE CHAR_LENGTH(SUBSTRING_INDEX(CAST(amount AS CHAR), '.', -1)) > 2;
```

结果：

| id | bill_id | repay_date | amount | CAST AS CHAR | created_at |
|---|---|---|---|---|---|
| 294 | 561 | 2026-10-29 | 6.739999999999999 | `6.739999999999999` | 2026-10-30 00:01:32 |

这是「按比例/差额拆分还款时用 float 做除法或减法」留下的存储残留。该行属于账单 561（账单金额 `4,232.64`，已还 `4,232.64`，两者一致），说明它**没有造成错账**，只是金额字段里唯一的浮点脏值。迁 `DECIMAL(12,2)` 后会存为 `6.74`，属于**修好**，但仍是全库唯一一处「金额值本身发生变化」的行，必须在对账报告里单独签字确认。

### 2.4 跨表勾稽基线（迁移前后必须完全不变）

| 勾稽项 | 迁移前基线 |
|---|---|
| 网贷账单已还合计 vs 还款明细（实付+优惠） | 652,207.31 = 652,207.31（347 张账单 / 299 条还款） |
| 手机卡余额 vs 期初+流水 | 119.76 = 60.36 + 59.40 |
| 旅行实付 vs 原价-优惠 | 2,566.86 = 2,805.89 - 239.03 |
| 网贷债务金额 vs 剩余（26 行中 7 行 remaining=NULL） | 213,094.43 vs 179,708.26 |
| 外汇 pnl/手续费/隔夜费 vs 资金流水 | -2,599.04 / -175.32 / -2.37；资金 9,206.16 |
| 房租期次合计 vs 月租合计 | 23,552.45 vs 9,933.61 |

---

## 3. 风险点（`Float` → `Numeric` 后 Python 侧变 `Decimal`）

先说行为验证结果（Pydantic 2.12.5 / FastAPI 0.135.1）：

| 表达式 | 结果 |
|---|---|
| `0.0 + Decimal("1")` | **TypeError** |
| `Decimal("1") + 0.0` | **TypeError** |
| `defaultdict(float)["k"] += Decimal` | **TypeError** |
| `Decimal("2") // 1.5` | **TypeError** |
| `sum([Decimal…])` / `round(Decimal, 2)` / `f"{Decimal:,.2f}"` / `f"{Decimal:g}"` | 正常 |
| `max(0.0, Decimal("-1"))` | 返回 **float 0.0**（混算隐患） |
| `Decimal("6.74") == 6.74` | **False**（float 6.74 二进制不精确；任何跨类型精确相等断言都会挂） |
| `json.dumps({"x": Decimal("1.1")})` | **TypeError** |
| Pydantic `x: float` 接收 `Decimal("6.739999999999999")` | 正常转 float，JSON 输出 `6.739999999999999` |
| `jsonable_encoder({"x": Decimal("1.10")})` | `{"x": 1.1}` |

### R1｜P0：聚合累加器「`float` 初值 + `Decimal`」→ 必现 500（13 文件 / 16 处）

| 风险点 | 位置 | 触发路径 | 等级 |
|---|---|---|---|
| `combined_rent = 0.0` 后 `+= base * …`（base 来自 `actual_monthly_rent`） | `backend/app/api/routes/finance/overview.py#L85-L91` | `GET /finance/overview`，有住房即崩 | P0 |
| 同上（报告版） | `backend/app/services/finance_report.py#L314-L320` | 生成财务报告即崩 | P0 |
| `by_category["actual"] = 0.0` 后 `+= r.actual_price`；`by_date = defaultdict(float)` | `backend/app/services/finance_report.py#L176-L185` | 旅行报告生成即崩 | P0 |
| `monthly/by_platform/by_ledger/by_category = defaultdict(float)` 后 `+= r.total_price` | `backend/app/api/routes/finance/shopping.py#L213-L216, L238-L244` | 购物统计即崩 | P0 |
| `by_category = defaultdict(float)` 后 `+= r.actual_price` | `backend/app/api/routes/finance/travel.py#L110-L114` | 旅行统计即崩 | P0 |
| `by_category.get(cat, 0.0) + r.amount` | `backend/app/api/routes/finance/subscriptions.py#L55` | 订阅统计即崩 | P0 |
| `by_month.get(key, 0.0) + r.amount`（账单） | `backend/app/api/routes/finance/loans.py#L85` | 账单按月统计即崩 | P0 |
| `by_month.get(key, 0.0) + r.amount`（还款） | `backend/app/api/routes/finance/loans.py#L229` | 还款按月统计即崩 | P0 |
| `current - amount`（`current` 为 Decimal，`amount` 来自 Pydantic float） | `backend/app/api/routes/finance/debts.py#L142, L237` | 债务还款/修改即崩 | P0 |
| `balance_total = 0.0` / `credit_total = 0.0` 后 `+= r.balance / r.credit_limit` | `backend/app/api/routes/lifestyle/cards.py#L302-L310` | 银行卡统计即崩 | P0 |
| `by_month = defaultdict(float)` 后 `+= b.amount` | `backend/app/api/routes/lifestyle/cards.py#L370-L372` | 扣账账单统计即崩 | P0 |
| `bonus_credit/bonus_loss/bonus_expired = 0.0` 后 `+= f.amount` | `backend/app/api/routes/investment/forex.py#L257-L268` | 外汇统计（有体验金）即崩 | P0 |
| `by_date.setdefault(..., 0.0)` 后 `+ r.amount` | `backend/app/api/routes/investment/funds.py#L40-L43` | 资金动态统计即崩 | P0 |
| `s["pnl"] = 0.0` 后 `+ _net(t)`；`daily = defaultdict(float)` | `backend/app/services/investment_report.py#L75-L85` | 投资报告即崩 | P0 |
| `opening[...] = opening_balance or 0.0`（Decimal）`+ sums`（float） | `backend/app/services/phone_billing.py#L96-L98, L117` | 手机卡余额/列表即崩 | P0 |
| `remaining = max(0.0, Decimal)`；`penalty = remaining * penalty_rate / 100 * days` | `backend/app/services/notification/scanner.py#L308-L310` | 逾期提醒；`remaining == 0` 时 `0.0 * Decimal` → 崩 | P0（边界） |
| `bought_pills = defaultdict(float)` 后 `+= (p.quantity or 0) * per` | `backend/app/services/med_stock.py#L39-L42` | **仅当 `quantity` 也迁 Numeric** 才崩；本方案不迁数量列 → 降至 P2 | P2 |

### R2｜P1：JSON 序列化

- 现有 Pydantic 响应模型的金额字段以 `float` 声明（`backend/app/schemas/finance.py#L38-L320` 的 `amount/total_price/price/balance/credit_limit/pnl` 等）。Pydantic 2 会把 `Decimal` 宽松转成 `float`，**JSON 输出形态不变**（已实测）。
- 直接 `json.dumps` 的非 Pydantic 路径：`backend/app/services/finance_report.py`、`investment_report.py`、`lifestyle_report.py`、`report_scheduler.py`、`finance/reports.py`、`travel.py`、`investment/reports.py`。已逐一核对：这些 `content` 里放的是 `f"¥{x:,.2f}"` 等**字符串**，未嵌入裸 Decimal；`backup_service.py#L32-L39`（`_serialize_value`）已显式处理 Decimal；`activity_logger.py#L239-L241` 处理的是已解析 JSON 响应体（float）。→ 只要保持「响应走 Pydantic / 报表只放格式化字符串」，`json.dumps` 不会因 Decimal 失败。**风险中低**，但新增报表代码必须遵守该约定。

### R3｜P1：比较 / 排序

- SQL 层 `ORDER BY`、`SUM`、`ROUND` 对 DECIMAL 正常；Python `sorted()`、`-x` 对 Decimal 正常（已实测）。
- `Decimal("6.74") == 6.74` 为 **False**：现有测试里唯一涉及金额的精确断言是 `backend/tests/test_phone_billing.py#L31-L34`，它作用于**纯 float 辅助函数**，不受影响。但未来任何「读库金额 == float 字面量」的断言都会失败，需改用 `Decimal("6.74")` 或 `pytest.approx`。
- 迁移后 `bill.amount - bill.paid_amount <= 1e-2`、`Decimal <= 1e-2` 等跨类型比较是合法的（已实测 True），无需改。

### R4｜P1：写入路径

- `FinanceRepayment(**payload.model_dump())`、`t.amount = round(payload.amount, 2)`（`backend/app/api/routes/finance/rent.py#L61, L91`）等仍以 **float** 写入 DECIMAL 列。MySQL 8 + STRICT 模式下会按分四舍五入并产生 note，不会报错；但依赖驱动隐式转换不是长期方案。建议在请求 schema 或 ORM 赋值处显式 `Decimal(str(value))`，避免「同一金额在 Python 与库里不同」。

### R5｜P2：现有测试断言

- 全量测试基线为内存 SQLite（`backend/tests/conftest.py#L28-L39`），`Numeric` 在 SQLite 上同样返回 `Decimal`，因此**只要某个聚合接口有测试覆盖，改模型后就会立刻暴露 R1**。
- 但当前测试只覆盖 CRUD 与纯函数：`test_crud.py#L40` 只断言字段名；`test_read_relax_finance.py` / `test_read_relax_investment.py` 只测 schema 约束放宽；`test_phone_billing.py` 只测 float 辅助函数。**聚合接口（overview / 各 stats / 报告生成）缺乏回归测试**，这是迁移最大的流程风险。
- 建议在 Phase 1 同步补：`/finance/overview`、`/finance/loans/stats`、`/finance/shopping/stats`、`/investment/forex/stats`、`/lifestyle/cards/stats`、三类报告生成、通知扫描（逾期分支）。

### R6｜P2：Alembic / 迁移脚本

- 基线迁移 `943429348ec7_baseline_...py` 中 `finance_loan_bills` 写 `sa.Float()`、`finance_repayments` 写 `sa.Double()`，但现网这两张表都已是 `double`（`loan_bills` 属于 Float→double 漂移）。新迁移必须显式 `existing_type=sa.Double()`（这两张表）与 `sa.Float()`（其余），否则在 MySQL 上可能生成错误的 MODIFY。
- 金额列均无索引/外键 → 不会触发约束重建；但 MySQL 对 `FLOAT/DOUBLE → DECIMAL` 走 **COPY** 算法，表会短暂只读（见第 4 节）。

### R7｜P2：前端 / 移动端展示

- 网页端 `frontend/src/lib/format.ts#L29-L65` 只接受 `number`，后端 JSON 仍是数字 → 无影响。
- 移动端 `mobile/lib/core/models/*.dart` 使用 `_toDouble(json['amount'])` 或 `(json['price'] as num).toDouble()`（如 `investment_models.dart#L74`、`lifestyle_models.dart#L86`）。**只要后端始终输出 JSON number 就安全**；若某接口把 Decimal 以字符串输出，Flutter 的 `as num` 会直接抛异常。需在验收用例里断言「字段类型是 number 而非 string」。

---

## 4. 迁移方案对比

| 维度 | ① 直接 `ALTER TABLE … MODIFY col DECIMAL(12,2)` | ② 新增列 + 双写回填 + 切换 | ③ 应用层只做 Decimal 化、不改库 |
|---|---|---|---|
| 做法 | 在维护窗口逐表改列；同步改 ORM `Numeric(12,2)` | 加 `amount_dec` 新列 → 双写 → 回填 → 读新列 → 删旧列 | 只把 Python 侧 `float` 换成 `Decimal`/quantize，DB 仍 FLOAT/DOUBLE |
| 停机窗口 | 每表 COPY 重建；最大表 4,277 行、3862 行量级，单表亚秒级；44 列合计可控制在 **1 分钟内**（建议仍选低峰窗口） | **接近 0 停机**，但要跨两个发布周期，且回填期间要双读比对 | **0 停机** |
| 回滚难度 | 低：反向 `MODIFY` 回 `FLOAT/DOUBLE`；数据 ≤2 位小数，可逆 | 中高：要回退双写逻辑、删新列、确认无脏数据；回填脚本需幂等 | 低：只回滚代码 |
| 数据丢失风险 | **极低**：仅 1 行（id=294）由 `6.739999999999999` → `6.74`；无 3 位小数金额被截断（已体检） | 低，但回填/双写窗口内若有写请求，必须处理「旧列新列不一致」 | **高（逻辑上）**：DB 仍是 FLOAT，重启/重读后 4 字节精度照旧，问题没真正解决 |
| 代码改动 | 44 列模型 + Alembic + R1 的 16 处修复 | 44 列模型×2 + 双写/回填/开关 + R1 修复 + 更多测试 | 只改 Python 类型与四则运算；**不改模型**，但需全链路 Decimal 化 |
| 优点 | 一次到位、结构最干净、查询/聚合天然精确 | 可灰度、可回退，适合超大表 | 风险最小、可立即做 |
| 缺点 | 需短窗口 + 必须同批修代码 | 工程量大、双写期一致性复杂，本项目数据量小（最大 4k 行），收益不划算 | 治标不治本，长期仍漂移 |
| 适配结论 | **推荐作为最终形态（Phase 3）** | **不推荐**（数据量小而复杂度高） | **推荐作为 Phase 1 的前置加固**，但不能作为最终方案 |

---

## 5. 对账手段：如何证明「只改精度、不改金额」

### 5.1 迁移前快照（本次已产出基线，可复现）

逐表逐列记录 4 个值：`COUNT(*)`、`COUNT(col)`、`SUM(col)`、`SUM(ROUND(col,2))`，再记录 `MAX(ABS(col-ROUND(col,2)))`。第 2.2 节即本库 2026-11-07 的基线。

```sql
-- 对每个 (表, 列) 执行；结果写入迁移记录表/JSON 文件
SELECT COUNT(*) AS rows,
       COUNT(`col`) AS non_null,
       SUM(`col`) AS sum_raw,
       SUM(ROUND(`col`, 2)) AS sum_2dp,
       MAX(ABS(`col` - ROUND(`col`, 2))) AS max_row_drift,
       SUM(ABS(`col` - ROUND(`col`, 2))) AS sum_drift
FROM `表名`;
```

### 5.2 行级逐条比对（证明「没有偷偷改金额」）

迁移前把每行「分位值」落盘，迁移后与新列逐行比对：

```sql
-- 迁移前：FLOAT/DOUBLE → 统一格式化成 2 位字符串
SELECT id, FORMAT(`col`, 2) AS cents FROM `表名` ORDER BY id;

-- 迁移后：DECIMAL(12,2) 本身就是 2 位字符串
SELECT id, CAST(`col` AS CHAR) AS cents FROM `表名` ORDER BY id;
```

用 Python 比对两张 `{id: cents}` 字典：

```python
# 只读比对伪代码
before = {row_id: cents for row_id, cents in before_rows}   # FORMAT(...,2)
after  = {row_id: cents for row_id, cents in after_rows}    # CAST AS CHAR
diff = {k: (before.get(k), after[k]) for k in after if before.get(k) != after[k]}
assert diff == {} or diff == {294: ("6.74", "6.74")}  # 唯一允许差异行
```

若要整表一次性校验，可用哈希（需先放大 `group_concat_max_len`）：

```sql
SET SESSION group_concat_max_len = 100000000;
-- 迁移前
SELECT MD5(GROUP_CONCAT(CONCAT_WS(':', id, FORMAT(`col`, 2)) ORDER BY id SEPARATOR '|')) FROM `表名`;
-- 迁移后（列已 DECIMAL(12,2)，固定两位）
SELECT MD5(GROUP_CONCAT(CONCAT_WS(':', id, CAST(`col` AS CHAR)) ORDER BY id SEPARATOR '|')) FROM `表名`;
```

> 注意：MySQL 的 `FORMAT` 与 DECIMAL 赋值对 `x.xx5` 都按「远离零」舍入，本项目金额列没有第 3 位为 5 的值（唯一脏值是 `…9999`），所以哈希可比。若未来出现 `.005`，需改用 `CAST(col AS DECIMAL(30,10))` 统一口径再比对。

### 5.3 跨表勾稽复核（业务口径）

迁移后重跑 2.4 的 6 组 SQL，要求与基线**逐分一致**：

```sql
-- 1) 账单已还 vs 还款明细
SELECT ROUND(SUM(paid_amount),2) FROM finance_loan_bills;
SELECT ROUND(SUM(amount + COALESCE(discount,0)),2) FROM finance_repayments;  -- 必须相等

-- 2) 手机卡余额 vs 期初 + 流水
SELECT ROUND(SUM(balance),2) FROM lifestyle_phone_cards;
SELECT ROUND(SUM(opening_balance),2) FROM lifestyle_phone_cards;
SELECT ROUND(SUM(amount),2) FROM lifestyle_phone_ledgers;                    -- 前两行之和必须等于第一行

-- 3) 旅行实付 vs 原价 - 优惠
SELECT ROUND(SUM(original_price),2), ROUND(SUM(discount),2), ROUND(SUM(actual_price),2),
       ROUND(SUM(original_price - discount),2)
FROM finance_travel_details;                                                 -- 第 3、4 列必须相等

-- 4) 外汇「盈亏 + 手续费 + 隔夜费」按日/按品种重算，与迁移前报告快照比对
```

### 5.4 验收判定标准

1. 44 列 × 每行：`before cents == after cents`，**仅允许** `finance_repayments.id=294` 一处；
2. 44 列的 `SUM` 原值 vs `SUM(ROUND)` 差异 **≤ 0.004 元**（FLOAT 精度噪声上限）；
3. 2.4 的 6 组勾稽全部一致；
4. 全量 `pytest` 无回归；新增 6 类聚合接口用例；
5. 抽查网页端 + 移动端：金额字段 JSON 类型为 number、展示金额与迁移前一致。

---

## 6. 建议（最小可行顺序）

### 6.1 明确结论

**不建议现在做「44 列一次性全量迁移」。** 不是技术不可行，而是**当前收益/风险不划算**：

- 收益侧：现网 44 个金额列中 43 列本来就是整数或 2 位小数，唯一 1 行脏值可单独修；迁移解决的是「未来长期漂移」，不是当前可见错账。
- 风险侧：13 个文件、16 处 P0 `float + Decimal` 会当天 500，且聚合/报告/通知路径缺回归测试；必须先补测试再改模型。

### 6.2 最小可行实施顺序（推荐）

| 阶段 | 内容 | 是否改库 | 可独立发布 |
|---|---|---|---|
| **Phase 0** | 修正 `finance_repayments.id=294`：`UPDATE … SET amount=6.74 WHERE id=294`（先备份该行） | 是（单行数据，非 DDL） | 是 |
| **Phase 1** | 代码 Decimal 加固：把 R1 的 16 处 P0 混算点改 `Decimal("0")`；边界处 `float()`；`debts.py` 的 `current - amount` 统一 Decimal；`phone_billing` 的 `opening` 统一 Decimal；补 6 类聚合接口 + 报告 + 逾期扫描回归测试。**模型仍 Float，行为零变化** | 否 | 是 |
| **Phase 2** | 比率/价格列单独迁移：`rate_to_cny DECIMAL(12,6)`、`penalty_rate/interest_rate DECIMAL(6,4)`、外汇 `open/close_price DECIMAL(12,4)`、`lot_size DECIMAL(10,2)` | 是（6 列） | 是（需 Phase 1 已完成） |
| **Phase 3** | 44 个金额列 → `DECIMAL(12,2)`：模型 + Alembic（显式 `existing_type`），低峰窗口执行；跑第 5 节对账 | 是（44 列） | 是 |

### 6.3 不要做什么

- 不要用方案 ②「新列双写」——最大表仅 4,277 行，双写/回填/切换的复杂度远高于收益。
- 不要用方案 ③「只改应用层 Decimal」当最终方案——库仍是 FLOAT，重新读取后精度照旧，问题没有真正解决。
- 不要把 `open_price/close_price`、`rate_to_cny`、`penalty_rate` 塞进 `DECIMAL(12,2)`——会真实改价/改费率。
- 不要把 `health_body`、`health_checkup`、`health_steps` 等**测量值**一并迁移——不属于金额口径，且会牵动体脂秤与健康报告。
- 不要在未补聚合接口测试前先改模型——`pytest` 现有覆盖不足以拦住 R1。

### 6.4 一句话给决策层

> **金额精度问题在数据层目前「几乎不存在」（仅 1 行脏值、合计漂移 0.0033 元），但在代码层「遍地是雷」（16 处 P0 float/Decimal 混算）。所以：先花小成本把代码改到 Decimal 安全（不改库），再择机做 44 列 DDL；本轮不做全量迁移。**
