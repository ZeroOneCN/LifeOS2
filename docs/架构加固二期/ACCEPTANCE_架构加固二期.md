# ACCEPTANCE — 架构加固二期（批 1）

> 阶段：6A 流程 · 阶段五/六（Automate / Assess）
> 上游文档：[ALIGNMENT](file:///c:/Code/LifeOS2/docs/架构加固二期/ALIGNMENT_架构加固二期.md) / [DESIGN](file:///c:/Code/LifeOS2/docs/架构加固二期/DESIGN_架构加固二期.md) / [TASK](file:///c:/Code/LifeOS2/docs/架构加固二期/TASK_架构加固二期.md)
> 执行日期：2026-11-02

## ⚠️ 醒目警告（务必遵守）

> **带数据的库禁止执行 `alembic downgrade base`。**
> 生产库 `lifeos2` 只是被 `stamp` 到 baseline（版本指针），库里的 61 张表并不是由 baseline 的 `upgrade()` 创建的。
> 一旦在生产库执行 `downgrade base`，baseline 的 `downgrade()` 会**逐张删除全部 61 张表**，数据将不可恢复。
> 生产库只允许：`alembic upgrade head`（前向迁移）、`alembic stamp <rev>`（写版本指针）。
> 回滚验证只能在一次性空库（如 `lifeos2_baseline_tmp`）中进行。

## 0. 最终结论（9 个候选唯一键：7 已落库 / 2 已取消）

- **7 条唯一约束已落库并完成模型同步**（见第 2 节）。
- **2 条取消**：`health_medication (user_id, record_date, medicine_name)` 与 `finance_loan_bills (user_id, platform_id, bill_month)`。经用户确认，这两组数据均为真实正确的业务数据，合法数据本身会撞键，唯一键不成立；若未来要加约束，必须重新设计键（如业务流水号等不可变标识），**不得使用金额等可变业务字段**。
- 本批**未删除、未修改任何业务数据**，未新增批 2 迁移。

## 1. 完成状态

| 任务 | 内容 | 状态 | 提交 |
|---|---|---|---|
| P2-T03 | Alembic 初始化（`backend/alembic/`，连接串取自 `settings.DATABASE_URL`，`alembic.ini` 无密码） | ✅ 完成 | `0f4a521` |
| P2-T04 | baseline 生成：空库 `upgrade head` 建出 61 表 + 11 条复合索引，`downgrade base` 可清空 | ✅ 完成 | `0f4a521` |
| P2-T05 | 生产库只 `stamp 943429348ec7`（1 行版本号，无建表 DDL） | ✅ 完成 | 无代码提交 |
| P2-T06 | 11 条索引写入模型 `__table_args__`；删除 `db_indexes.py`、`Base.metadata.create_all`；README 改为「先跑迁移」 | ✅ 完成 | `0f4a521` / `02f768a` |
| P2-T07 | 批 1 唯一约束：7 张表全部加约束（存量重复 0 组） | ✅ 完成 | `0d3d3e9` |
| P2-T08 | 重复数据处置（`health_medication` 1 组、`finance_loan_bills` 1 组） | ⛔ 已终止（数据经用户确认无误，无需处置） | 无代码/数据提交 |
| P2-T09 | 批 2 唯一约束（上述 2 张表） | ⛔ 已取消（唯一键不成立） | 无迁移提交 |
| P2-T10 | `IntegrityError → 409`（创建接口），语义与 `_raise_if_conflict` 一致 | ✅ 完成 | `efc0ca4` |
| P2-T11 | 全量回归与启动自检 | ✅ 完成（见第 3 节） | 无代码提交 |
| P2-T12 | 文档与进度同步 | ✅ 完成（本文件 + `说明文档.md`） | 本提交 |

## 2. 本次新增的 7 条唯一约束

执行前对 7 张表做只读重复检测（按唯一键 `GROUP BY ... HAVING COUNT(*) > 1`），**全部为 0 组重复**，无跳过。

| # | 表 | 唯一键 | 约束名 | 重复组数 |
|---|---|---|---|---|
| 1 | `health_steps` | `user_id, record_date, period` | `uq_steps_user_date_period` | 0 |
| 2 | `health_vitals_sleep` | `user_id, record_date` | `uq_vitals_user_date` | 0 |
| 3 | `health_med_stock` | `user_id, medicine_name` | `uq_medstock_user_name` | 0 |
| 4 | `finance_utilities` | `user_id, housing_id, bill_month, fee_type` | `uq_util_user_house_month_type` | 0 |
| 5 | `finance_rent_terms` | `user_id, housing_id, term_no` | `uq_rentterm_user_house_no` | 0 |
| 6 | `lifestyle_card_bills` | `user_id, phone_card_id, bill_month` | `uq_cardbill_user_card_month` | 0 |
| 7 | `notifications` | `user_id, source` | `uq_notif_user_source` | 0 |

迁移文件：[3fd6b94691f3_add_7_unique_constraints.py](file:///c:/Code/LifeOS2/backend/alembic/versions/3fd6b94691f3_add_7_unique_constraints.py)
版本链：`943429348ec7`（baseline）→ `3fd6b94691f3`（本批约束）。

## 3. 验证证据

| 验证项 | 结果 |
|---|---|
| `python -m pytest` | `44 passed in 0.85s`（原 41 + 新增 3 条 409 用例） |
| `alembic upgrade head` | `Running upgrade 943429348ec7 -> 3fd6b94691f3`，退出码 0 |
| `alembic current` | `3fd6b94691f3 (head)` |
| `information_schema.table_constraints` | 7 条 `uq_` 约束全部存在 |
| `SHOW CREATE TABLE health_steps` | 可见 `UNIQUE KEY uq_steps_user_date_period` |
| 重复插入步数（同 user/日期/时段） | 201 → 409，`{"detail":"该日期已存在相同时间段的步数记录，请勿重复添加"}` |
| 重复插入水电账单（无业务唯一校验，走 DB 约束） | 201 → 409，`{"detail":"已存在相同记录"}` |
| 后端启动 + `GET /api/v1/health` | 200，`{"status":"ok",...}`，database ok、schedulers running |
| 模型与库差异 | 67 条**历史漂移**（与本次 7 条约束无关，唯一约束增删条目数为 0） |
| 工作区 | `git status` 干净；`backend/.env` 被 gitignore，未被跟踪 |

## 4. 未完成 / 延后事项

1. **P2-T08 已终止、P2-T09 已取消**：`health_medication` 与 `finance_loan_bills` 的两组记录经用户确认**均为真实正确的业务数据**，不做任何删除或修改；对应的两个候选唯一键不成立，不新增约束。未来若需约束，须重新设计不可变业务键。
2. **67 条历史漂移专项**：模型与现有库在索引命名、可空性/默认值、列注释、金额列类型（`DOUBLE(asdecimal)` ↔ `Float`）上存在 67 条差异，全部早于本批工作。`alembic check` 目前无法作为 CI 门禁，需单独立项对齐（涉及 `health_medication` 与 `finance_loan_bills`，需单独授权）。
3. **生产库回滚演练**：因风险过高未执行；`upgrade`/`downgrade` 的往返验证只在一次性空库完成，该临时库已删除。

## 5. 遗留风险

- **NULL 语义**：MySQL 唯一索引不约束 NULL。`notifications.source` 与 `finance_utilities.housing_id` 允许为空，此类行仍可能重复；如需强约束，应先把列改为 NOT NULL 或改用其它业务键（超出本批范围）。
- **迁移前必须先备份**：任何后续 `upgrade` 前仍按项目约定先 `mysqldump`。
- **autogenerate 不可直接全量执行**：因存在 67 条漂移，后续所有迁移必须像本批一样只写目标变更、人工剔除无关 diff。

## 6. T08 只读调查证据（未处置，仅登记）

### 6.1 两组记录的字段事实

| 表 | 重复键 | 行 id | 字段差异 |
|---|---|---|---|
| `health_medication` | `(user_id=1, record_date=2026-01-16, medicine_name=异维A酸软胶囊)` | 293、294 | **14 个字段全部相同**，包括 `created_at` / `updated_at` 均为 `2026-09-04 00:17:09`；`dose_lunch=1`、`taken_lunch=1`，其余剂量与备注均为 0/NULL |
| `finance_loan_bills` | `(user_id=1, platform_id=9 房租水电, bill_month=2024-08-01)` | 380、386 | 仅 `amount` / `paid_amount` 不同：380 为 `499.88`、386 为 `471.26`；`due_date` 均为 `2024-08-30`，`status` 均为 `cleared`。两条各自关联独立还款：380→还款 82（`2024-07-30`，499.88），386→还款 87（`2024-08-30`，471.26） |

**用户最终确认**：以上两组均为真实正确的业务数据，不做删除或修改；因此两个候选唯一键不成立（合法数据会撞键），T09 取消。

### 6.2 导出文件（只读、未提交）

| 文件 | 位置 | 回读校验 |
|---|---|---|
| `dup_health_medication_20261102_191707.csv` | `backend/backups/`（已 gitignore） | 14 列、2 行、列宽一致 |
| `dup_finance_loan_bills_20261102_191707.csv` | `backend/backups/`（已 gitignore） | 13 列、2 行、列宽一致 |

### 6.3 附：同类“还款早于账单月”全表只读扫描（仅登记，不处置）

- 全表 347 笔账单中，`repay_date < bill_month` 的共 **4 笔**：`380`（房租水电）、`561`（广发）、`569`（广发）、`572`（花呗）；早于账单月的还款金额合计 **708.40**（其中 380 为 499.88，561/569/572 合计 208.52）。
- 判断：`561`/`569`/`572` 属正常提前或分批还款；`380` 虽形似月份错标，但用户已确认数据正确，**按现状保留，不据此修改任何数据**。
- `bill_month` 与 `due_date` 月份矛盾：**0 条**（343 笔同月到期，4 笔美团为次月 3 日到期，属正常跨月）。
