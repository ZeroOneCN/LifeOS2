# ALIGNMENT — 架构加固二期（结构地基）

> 阶段：6A 流程 · 阶段一（Align）
> 日期：2026-11-02
> 范围：仅后端 `backend/`；前端不参与
> 本文件状态：**待审批**（审批通过后才进入 DDL 执行）

## 1. 背景

第一批 8 条缺陷修复（登录审计落库、活动日志脱敏、备份权限、缓存 key、批量 PATCH 白名单、JWT 启动校验、复合索引 DDL、`/sessions` 管理员守卫）已完成并推送 master。这批修复解决的是「单点失效」，但没有改变**结构性地基缺失**：数据库没有版本管理、索引靠应用启动副作用、业务唯一性只靠应用代码自觉、调度与限流是进程内状态、核心计算无任何回归测试。

二期目标：把「数据库结构」与「测试」这两块地基补上，使后续任何结构调整都可回滚、可验证。

## 2. 本阶段覆盖的审计条目

| 编号 | 问题 | 代码证据（已核实） | 本次是否处理 |
|------|------|--------------------|--------------|
| A1 | 无迁移版本管理，`Base.metadata.create_all` 只能建新表，不能改已有表结构 | [main.py](file:///c:/Code/LifeOS2/backend/app/main.py#L43)；仓库无 Alembic 目录、无 `alembic_version` 表 | ✅ 引入 Alembic + baseline stamp |
| A3 | 索引是「应用启动期补丁」而非迁移资产；模型 `__table_args__` 里没有复合索引声明 | [db_indexes.py](file:///c:/Code/LifeOS2/backend/app/core/db_indexes.py#L16-L28) 11 条索引；全库仅 3 处 `index=True` 单列索引之外无复合索引声明 | ✅ 11 条索引迁入模型，补丁模块下线 |
| A4 | 业务唯一性无数据库约束，仅靠应用层判断；并发/脚本导入可写出重复记录 | 全库仅 3 处 `unique=True`：[user.py L16](file:///c:/Code/LifeOS2/backend/app/models/user.py#L16)（account）、[user_session.py L17](file:///c:/Code/LifeOS2/backend/app/models/user_session.py#L17)（refresh_token_hash）、[lifestyle.py L174](file:///c:/Code/LifeOS2/backend/app/models/lifestyle.py#L174)（dedup_key）；其余业务表无复合唯一约束 | ✅ 按候选清单分批加唯一约束（需先处置存量重复） |
| A6 | 无测试体系：无 `tests/`、无 pytest 依赖、无 CI 入口 | 仓库根与 `backend/` 无测试目录；`requirements.txt` 无测试依赖 | ✅ 本准备段已搭好（见第 5 节） |
| B3 | 调度是进程内 APScheduler，多实例会重复执行；仅部分任务有去重键 | [notification/scheduler.py L111-L166](file:///c:/Code/LifeOS2/backend/app/services/notification/scheduler.py#L111-L166)（4 个 job）、[backup_scheduler.py L176+](file:///c:/Code/LifeOS2/backend/app/services/backup_scheduler.py#L176)、[report_scheduler.py L315+](file:///c:/Code/LifeOS2/backend/app/services/report_scheduler.py#L315)；`max_instances=1` 只约束单进程 | ⚠️ 本阶段**只登记风险**，不做多实例改造（超范围） |
| C2 | IP 限流是进程内字典，重启/多实例即失效 | [auth.py L38-L57](file:///c:/Code/LifeOS2/backend/app/api/routes/auth.py#L38-L57) `_ip_request_log: dict[str, list[float]]` | ⚠️ 登记风险，不改造 |
| C3 | 账号锁定依赖 `login_audits` 的应用时钟与无约束计数；同账号并发登录时计数存在竞争 | [security.py L142-L167](file:///c:/Code/LifeOS2/backend/app/core/security.py#L142-L167)、[security.py L170-L226](file:///c:/Code/LifeOS2/backend/app/core/security.py#L170-L226) | ⚠️ 登记风险；唯一约束落地可缓解并发写入重复，但不解决时钟口径 |
| D1 | 高风险纯逻辑无回归测试（金额取整、跨月、药品库存、月租幂等、步数唯一性） | 本准备段已覆盖其中 5 组纯函数/轻量 ORM 用例（第 5 节） | ✅ 已建基建 + 首批用例 |

## 3. 已验证事实（附证据）

| 事实 | 证据 |
|------|------|
| 生产库 61 张表、模型 61 个，`Base.metadata.create_all` 在 lifespan 启动时执行 | `SHOW TABLES` 61 行；[main.py L43](file:///c:/Code/LifeOS2/backend/app/main.py#L43) |
| 11 条复合索引在现有库中**全部真实存在** | 准备段实测 `information_schema.statistics` 反查 11/11（上一提交 `a0f7425` 的验证输出） |
| `db_indexes.py` 已修正 3 条错误表名，当前为合法 MySQL DDL + 幂等 + warning | [db_indexes.py](file:///c:/Code/LifeOS2/backend/app/core/db_indexes.py) |
| 存量重复：9 个候选唯一键中仅 2 组重复 | 2026-11-02 对生产库只读统计（见下表） |
| 调度器共 3 个实例、6 个 job | 通知 4（`notify_daily_scan`、`notify_overdue_hourly`、`phone_billing_settle`、`cleanup_expired_sessions`）+ 备份 1（`backup_scheduled_scan`）+ 报告 1（`monthly_report_generate`） |
| 缓存为进程内 TTL 字典，失效按 key 前缀 | [cache.py L13-L46](file:///c:/Code/LifeOS2/backend/app/core/cache.py#L13-L46) |

### 3.1 存量重复只读统计（2026-11-02）

```
表名 | 分组键 | 总行数 | 重复组数 | 涉及行数 | 多余行数
health_steps | user_id, record_date, period | 3778 | 0 | 0 | 0
health_vitals_sleep | user_id, record_date | 24 | 0 | 0 | 0
health_medication | user_id, record_date, medicine_name | 470 | 1 | 2 | 1
health_med_stock | user_id, medicine_name | 1 | 0 | 0 | 0
finance_utilities | user_id, housing_id, bill_month, fee_type | 47 | 0 | 0 | 0
finance_rent_terms | user_id, housing_id, term_no | 19 | 0 | 0 | 0
lifestyle_card_bills | user_id, phone_card_id, bill_month | 16 | 0 | 0 | 0
notifications | user_id, source | 84 | 0 | 0 | 0
finance_loan_bills | user_id, platform_id, bill_month | 347 | 1 | 2 | 1
```

结论：**只有 2 处冲突**（`health_medication` 1 行多余、`finance_loan_bills` 1 行多余），其余 7 个候选键可直接加约束。

## 4. 范围边界

### 4.1 本阶段包含

1. Alembic 引入（baseline stamp 路径）、首个真实修订（唯一约束 + 索引声明归位）。
2. 11 条复合索引从启动补丁迁入模型 `__table_args__`，补丁模块下线。
3. 业务唯一约束（9 个候选键，按存量重复情况分批）。
4. 测试体系（pytest + 内存库夹具 + 首批高风险纯函数用例）。
5. 相关文档与进度同步。

### 4.2 明确不包含（本阶段不做）

| 不做的事 | 原因 |
|----------|------|
| 金额 `Float` → `Numeric/DECIMAL` 迁移 | 影响所有财务表与前端序列化，需单独评估与回归，属第三批 |
| 时区统一 | 涉及所有 `DateTime` 列与前端展示，需单独方案 |
| 多实例调度改造（分布式锁/单独 worker） | 属部署架构变更，不在「结构地基」范围 |
| 前端任何改动 | 前端由其他人负责 |
| 升级/锁定现有依赖版本 | 用户明确要求本次不碰 |
| 限流改造（IP 限流下沉到 Redis/DB） | 与多实例改造绑定，延后 |
| CI 平台接入 | 本阶段只保证 `pytest` 可在本地/CI 命令跑通 |

## 5. 本准备段已完成事项（不动 schema）

| 事项 | 产出 |
|------|------|
| 数据库全量备份 | `backend/backups/正式备份_20261102_183230.sql`，2,326,436 字节，mysqldump 退出码 0 |
| 测试依赖 | `backend/requirements-dev.txt`（`-r requirements.txt` + `pytest`，未升降任何版本） |
| 测试基建 | `backend/tests/conftest.py`（内存 SQLite + 用例级事务回滚）、`backend/pytest.ini` |
| 首批用例 | 5 个文件、41 个用例，全部通过（`41 passed`） |
| 存量重复检查 | 只读脚本统计，结果见 3.1，脚本未提交 |

## 6. 需要用户拍板的决策点

> 以下每条都影响后续 DDL，请在审批时逐条给出选择。

### 决策 1：存量重复数据怎么处置（**最高优先级**）

现状：`health_medication` 有 1 组重复（2 行）、`finance_loan_bills` 有 1 组重复（2 行）。

| 方案 | 做法 | 优点 | 风险 |
|------|------|------|------|
| A（推荐） | 先导出这 2 组明细到备份表/文件，保留 `id` 最大（最新）一行，删除旧行；然后加约束 | 约束可全量落地，数据损失最小且可回溯 | 删除 2 行历史记录（有备份） |
| B | 保留全部数据，只对「无重复」的 7 个表加约束，重复的 2 个表暂缓 | 零数据改动 | 2 个核心表长期无约束，A4 只解决 7/9 |
| C | 加约束前把重复行合并（剂量相加/金额相加） | 不丢业务量 | 合并口径需要人工确认，且 1 组已无法还原语义 |
| D | 加约束失败即中止迁移，人工处理后再跑 | 最安全 | 需要你手工介入，阻塞后续 |

**建议 A**：备份已完成（决策前可再导一次），删除前打印完整行内容供你确认。

### 决策 2：Alembic baseline 的落法

- 方案 A（推荐）：用**空库** autogenerate 生成完整 baseline 脚本（保证空库可一键重建 61 张表）；对现有生产库执行 `alembic stamp <baseline>`，**不执行任何 DDL**；之后只跑增量修订。
- 方案 B：直接在现有库 autogenerate（得到空脚本），把 baseline 标为空迁移。缺点：空库无法重建结构。
- 需确认：是否接受「生产库 stamp 一次」这一操作（它会写入 `alembic_version` 表，仅 1 行）。

### 决策 3：`create_all` 是否保留

- 方案 A（推荐）：移除 lifespan 里的 `Base.metadata.create_all`，schema 变更一律走 `alembic upgrade head`（手动/部署脚本执行），避免应用启动偷偷改结构。
- 方案 B：保留 `create_all` 作为开发便利，Alembic 只做增量。风险：两套真相并存，字段漂移仍可能发生。
- 需确认：是否接受「本地开发也要先跑 `alembic upgrade head`」。

### 决策 4：唯一约束冲突时的 API 行为

加约束后，绕过应用层校验的写入会抛 `IntegrityError`（当前会变成 500）。
- 方案 A（推荐）：在 `crud_router` 的统一写入口捕获 `IntegrityError`，映射为 **409 + 中文提示**（与现有 `_raise_if_conflict` 的 409 语义一致，不新增契约）。
- 方案 B：只加约束不改代码，接受极少数并发场景返回 500。
- 需确认：是否同意把 `IntegrityError` 统一映射为 409（属于错误处理增强，不改变成功路径契约）。

### 决策 5：`notifications(user_id, source)` 与 `finance_utilities(... housing_id ...)` 的 NULL 语义

MySQL 唯一索引对 NULL 是「彼此不相等」：`source IS NULL` 或 `housing_id IS NULL` 的行不会被约束去重。
- 方案 A（推荐）：接受该限制，仅约束非 NULL 组合（现有数据 0 重复，业务上 `source` 由扫描器生成、`housing_id` 允许为空）。
- 方案 B：为可空列设默认值（如 `source=''`、`housing_id=0`），让约束真正生效。会改变写入语义与历史数据。
- 需确认：选 A 还是 B。

### 决策 6：测试库选型

- 方案 A（推荐，已落地）：内存 SQLite + 事务回滚夹具；MySQL 专属行为另加 `@pytest.mark.mysql` 的独立 schema 夹具（后续按需）。
- 方案 B：所有用例都用独立 MySQL `lifeos2_test` schema（更真实，但本地/CI 必须有 MySQL，速度慢）。
- 需确认：是否接受当前方案，以及是否需要在二期就补 MySQL 夹具。

## 7. 验收标准

1. **备份**：`backend/backups/` 下存在本次时间戳备份，大小 > 2MB，`mysqldump` 退出码 0。
2. **Alembic**：空库执行 `alembic upgrade head` 可建出 61 张表；现有库 `alembic current` 显示 baseline；`alembic upgrade head` 不重复执行已完成的修订。
3. **索引归位**：11 条索引在模型 `__table_args__` 中声明；`db_indexes.py` 删除后重启，`information_schema` 仍显示 11 条索引；新库 `create_all`/迁移也能建出。
4. **唯一约束**：9 个候选键全部落地（或按决策 1 的 B 方案明确列出暂缓项）；重复数据处置有前后统计证据。
5. **回归**：`python -m pytest` 全绿；启动自检 `GET /api/v1/health` 为 `ok`；现有 API 成功路径契约不变。
6. **可回滚**：唯一定义的 down_revision 链完整；`alembic downgrade -1` 可撤销本轮新增约束/索引。

## 8. 执行前置条件

- 决策 1~6 已拍板。
- 本次备份文件确认可恢复（可先在测试库 `source` 一次验证）。
- 无其他人在同一时间改 `backend/app/models/`、`backend/app/api/crud.py`。
