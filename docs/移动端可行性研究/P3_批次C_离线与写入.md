# P3 批次 C：离线队列与写入（C1）

> 更新：2026-11-07 05:20　维护人：移动端
> 范围：本轮只做 **C1（离线队列骨架 + 打通一个写入动作）**，样本为「财务 → 记一笔支出」。
> 约束：只改 `mobile/`；不动 `frontend/`、`backend/`；`flutter analyze` 0 error / 0 warning。

---

## 一、C1 结论

| 项 | 结果 |
|---|---|
| 本地队列 | SharedPreferences 落盘（`outbox.queue.v1`），跨冷启动存活 |
| 断网保存 | 立即返回「已存本地，联网后自动同步」，无 HTTP 转圈 |
| 自动推送 | 恢复网络按 FIFO 推送；成功出队，失败保留可手动重试 |
| 幂等 | 客户端 `localId` + 失败后查重（补偿，不是真幂等） |
| 设置页可见 | 待同步条数 + 上次同步时间 + 立即同步 |
| 超时 | 连接 5s / 发送 10s / 接收 15s（原 10/15/20） |
| 接入范围 | 仅「创建支出」一条写操作，其余写操作留到 C2 |

---

## 二、存储选型与理由

**选型：SharedPreferences（复用现有 `PreferencesService`）**，整表 JSON 覆盖写。

理由：

1. **数据量小**：队列是「待推送的写操作」，正常只有个位数到几十条，整表序列化成本可忽略。
2. **必须跨冷启动存活**：SharedPreferences 是本地持久化文件，`init()` 在 `runApp` 前加载，首屏即可显示待同步条数。
3. **失败重试要能改状态**：每条记录的 `retryCount` / `lastError` 只在推送失败时变化，整表覆盖写正好满足，且不需要事务。
4. **不引入额外原生成本**：sqflite / drift 要建表、写迁移、处理 Android 端数据库句柄；Hive 也要额外初始化与生成适配器。C1 只为一条写操作打通链路，不值得为此新增依赖与迁移风险。
5. **可观测**：队列就是一个 JSON 数组，出问题可直接读偏好文件排查；后续若条目量增长或需要按状态查询，再迁 sqflite 也不影响上层接口（`OutboxController` 已封装读写）。

放弃方案：

- **sqflite / drift**：需要 schema 与迁移；当前查询模式是「取队首、按序推送」，用不上 SQL 索引。
- **Hive**：功能足够，但需要额外 box 初始化与 `TypeAdapter`，收益与成本不匹配。
- **文件直写**：要自己处理并发与损坏恢复，SharedPreferences 已由平台保证原子写。

队列键：

| 键 | 内容 |
|---|---|
| `outbox.queue.v1` | 队列 JSON 数组（整表） |
| `outbox.last_sync_at` | 上次成功推送时间（ISO8601） |

---

## 三、队列数据结构

`lib/core/queue/outbox_entry.dart`：

| 字段 | 类型 | 说明 |
|---|---|---|
| `localId` | String | 本地唯一 id（毫秒时间戳 + 进程内自增序号） |
| `opType` | String | 操作类型，C1 仅 `finance.shopping.create` |
| `payload` | Map | 请求体（`record_date` / `product_name` / `total_price` / 可选 `category_id`、`note`） |
| `createdAt` | String | 入队时间（ISO8601） |
| `retryCount` | int | 已失败次数，重试前用于判断是否走查重 |
| `lastError` | String? | 最近一次失败原因（UI 展示） |

JSON 键名：`local_id` / `op_type` / `payload` / `created_at` / `retry_count` / `last_error`。
冷启动解析失败（`FormatException`）时清空队列，避免坏数据导致启动失败。

---

## 四、网络状态

- 依赖：`connectivity_plus 7.3.2`（pub 包名 `connectivity_plus`；Android 侧实现包为 `dev.fluttercommunity.plus.connectivity`）。
- 监听：`Connectivity().onConnectivityChanged`，任何非 `none` 结果都视为「有网」。
- 断网时**不发起 HTTP**：`enqueueExpense` 先落盘并 `notifyListeners()`，页面立即出现「待同步」条目与 Snackbar，不经过网络层，因此不存在 15 秒转圈。
- 恢复网络时若有登录态，自动 `sync()`；若冷启动断网导致 `/auth/me` 未恢复，会先 `restore()` 再推送（`_recoverThenSync`），保证「联网即自动推送」在冷启动场景也成立。

流程：

```
点保存 → 校验金额/说明 → OutboxController.enqueueExpense(payload)
        → 写 SharedPreferences（await）
        → notifyListeners（列表出现「待同步」）
        → 在线：后台 sync()（不 await）；离线：直接返回
恢复网络 → connectivity 事件 → 需要时 restore() → sync()
        → FIFO：POST /finance/shopping/records
        → 成功：removeAt(0) + 落盘 + 更新 lastSyncAt
        → 失败：retryCount+1 + lastError + 落盘 + break（保留队列）
```

---

## 五、重复提交防护（补偿，不是真幂等）

**后端现状**：`POST /finance/shopping/records` 没有幂等键参数，也没有 `If-Match` / `Idempotency-Key` 支持，服务端不会拦截重复请求。

**客户端做法**：

1. 每条队列记录生成 `localId`，仅作本地标识与排查用，**不传给后端**（后端不认）。
2. 推送前若 `retryCount > 0`（说明之前失败过、可能已在服务端写入），先查重：
   - `GET /finance/shopping/records?start=日期&end=日期&page=1&page_size=200`
   - 比对 `record_date` 同一天 + `product_name` + `total_price` + `note` 完全一致
   - 命中则视为「上次其实已写入」，直接出队，不再 POST
3. 首次推送（`retryCount == 0`）不做查重，避免把用户当天同价同名的两笔正常消费误判成重复。

**如实说明：这是补偿，不是幂等。仍会重复的情况**：

- **首次推送「请求已到服务器、响应超时」**：第一次 `retryCount == 0`，失败后重试走查重，能挡住；
  但如果用户在**查重接口也超时**时继续重试，仍按失败保留，不会误删；一旦查重成功就能挡住。
- **两笔真实业务完全相同**（同一天、同名、同金额、同备注）：第二笔首次失败重试时会被查重误判为「已写入」而**漏写**（这是误判方向的代价，比重复写入更隐蔽）。
- **查重分页上限 200 条**：当天记录超过 200 条时，超出部分查不到，可能重复写入。
- **并发写入 / 多设备**：另一台设备在查重与 POST 之间写入同一条记录，仍会产生两条。
- **服务端写入成功但字段被改写**（例如后端补默认备注/分类）：查重的 `note` 比对会不命中，重试仍可能重复。
- **后端未来加了幂等键**：应改为传 `Idempotency-Key = localId`，查重逻辑即可删除。

---

## 六、超时改动

文件：`mobile/lib/core/config/app_config.dart`

| 项 | 原值 | 新值 |
|---|---|---|
| `connectTimeout` | 10s | **5s** |
| `sendTimeout` | 15s | **10s** |
| `receiveTimeout` | 20s | **15s** |

- 只在 `ApiClient` 的 Dio `Options` 生效，全局所有接口共用。
- 理由：局域网后端通常 <1s 可达；断网/飞行模式下 TCP 悬挂不应再等 10s。
- 副作用：
  - 弱网（如远距离 Wi-Fi、移动网络）下，原本 10s 内能连上的请求现在 5s 就失败，用户会更快看到「连接失败」并重试。
  - 报告接口响应约百 KB（B6a/B6b），`receiveTimeout` 从 20s 收到 15s，实测局域网仍在 1s 内返回，余量充足；若将来加导出/大文件接口需重新评估。
  - 超时变短不会造成写操作重复：写操作走离线队列，失败保留在队列，不丢数据。

---

## 七、真机实测记录（2026-11-07 05:0x–05:20）

设备：Android 真机（`com.lifeos.mobile` debug APK），后端 `192.168.8.103:9515`（真实 MySQL）。
基线：财务购物记录总数 **426**（今日 0 条）。

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 断网（关 Wi-Fi + 移动数据）后保存「C1-OFF-A ¥1.23」 | **立即**出现 Snackbar「已存本地，联网后自动同步」；流水页「待同步 共 1 条」，条目带「待同步」标记；「立即同步」置灰 |
| 2 | 设置页查看 | 「离线队列 / 待同步 1 条 / 上次同步 尚未同步」 |
| 3 | 杀进程（`am force-stop`）后冷启动，仍断网 | 队列仍在：待同步 **1 条**，金额/日期完整 |
| 4 | 恢复 Wi-Fi + 移动数据后重新安装并启动（冷启动在线） | 自动 `restore()` + 推送成功：待同步 0 条，「最近支出」出现 C1-OFF-A；服务端总数 426 → **427** |
| 5 | 运行中再次断网保存「C1-OFF-B ¥2.34」 | 待同步 1 条；恢复网络瞬间自动推送，但因 Wi-Fi 尚未拿到路由，5s 连接超时失败：**同步失败 + 可见错误「连接超时，请检查服务器地址与网络」+「立即同步」可点** |
| 6 | 点「立即同步」 | 推送成功：待同步 0 条，C1-OFF-B 补进「最近支出」；服务端 **428** |
| 7 | 把服务器地址改成不可达 `192.168.8.199:9515`，保存「C1-DEDUP-C ¥3.45」 | 推送失败：待同步 1 条、同步失败、错误可见、可手动重试 |
| 8 | 用后端官方接口写入一条同日期/同名/同额记录（模拟「服务端已写入但响应丢失」） | 服务端今日 3 条（含 C1-DEDUP-C 1 条） |
| 9 | 恢复正确服务器地址，点「立即同步」 | **查重命中，直接出队，未再 POST**：待同步 0 条，服务端 C1-DEDUP-C 仍只有 **1 条**（总数 429 未变成 430） |
| 10 | 设置页复查 | 「待同步 0 条 / 上次同步 11-07 05:15」 |

截图（`docs/移动端可行性研究/screenshots/`）：

- `p3_c1_offline_saved.png`：断网保存后的 Snackbar + 待同步条目
- `p3_c1_cold_start_persist.png`：冷启动后设置页仍显示 1 条
- `p3_c1_sync_failed.png`：推送失败的错误与「立即同步」
- `p3_c1_sync_success.png`：重试成功后队列清空、真实数据补上
- `p3_c1_settings_queue.png`：待同步 0 条 + 上次同步时间

测试数据清理：三条测试记录（id 434 / 435 / 436）已通过 `DELETE /finance/shopping/records/{id}` 删除，
复核总数回到 **426**、今日 **0** 条，未动数据库。

---

## 八、已知限制（留到 C2 或后续）

1. **只接入了「创建支出」**：账单、用药、体重、外汇等写操作仍走在线提交，断网时会失败。
2. **流水页只有「待同步 + 最近 5 条」**：完整分页流水列表未做，推送成功后的刷新只覆盖前 5 条。
3. **冲突策略未实现**：本轮没有「离线改某条记录、服务端同时改」的场景（没有离线编辑/删除），C2 接入编辑与删除时需定义谁赢。
4. **查重依赖分页上限 200 条**、且不含分类/账本字段，存在误判窗口（见第五节）。
5. **队列无条数上限**：极端长期离线会持续增长；后续可加上限或提示用户。
6. **失败不自动重试退避**：仅在连通性变化 / 登录成功 / 手动点击时重试，避免后台反复请求。
7. **SharedPreferences 队列是整表覆盖写**：条目量到数百条时写入成本上升，届时再迁 sqflite。

---

## 九、涉及文件

| 文件 | 变更 |
|---|---|
| `lib/core/queue/outbox_entry.dart` | 新增：队列条目模型 + JSON 序列化 |
| `lib/core/queue/outbox_controller.dart` | 新增：落盘、连通性监听、FIFO 推送、查重、手动重试 |
| `lib/core/storage/preferences_service.dart` | 新增字符串/布尔读写 |
| `lib/core/config/app_config.dart` | 超时 5/10/15s |
| `lib/core/app_scope.dart` | 注入 `OutboxController` |
| `lib/main.dart` | `runApp` 前 `outbox.init()` |
| `lib/features/finance/finance_expense_create_page.dart` | 新增：支出录入页（金额/说明/日期/分类/备注） |
| `lib/features/finance/finance_transactions_page.dart` | 重写：待同步 + 最近支出 |
| `lib/shared/widgets/add_record_fab.dart` | 「支出」跳转录入页 |
| `lib/core/router/app_router.dart` | `/finance/expense/new` |
| `lib/features/settings/settings_page.dart` | 离线队列卡（条数 / 上次同步 / 立即同步） |
| `pubspec.yaml` / `pubspec.lock` | 新增 `connectivity_plus 7.3.2` |

---

## 十、C2：用药打卡与外汇录入接入（2026-11-07 05:2x–05:5x）

> 范围：只改 `mobile/`；把离线队列接到「用药打卡」「外汇录入」，并加自动退避与条数上限。
> 边界：不做离线编辑/删除，冲突策略仍是「只在创建（或 PUT 幂等更新）类操作上排队」。

### 10.1 结论

| 项 | 状态 | 说明 |
|---|---|---|
| 用药打卡离线 | 完成 | 断网打卡本地立即生效并标「待同步」，联网自动推送（PUT 幂等） |
| 外汇录入离线 | 完成 | 保存即入队；列表顶部「待同步」临时卡；推送成功后临时卡消失、真实记录补上，不重复 |
| 自动退避 | 实现完成，未做完整真机时序验证 | 1s / 5s / 30s / 2min，第 5 次失败后停止自动重试，转手动 |
| 队列上限 | 实现完成，未实测 200 条 | `maxEntries = 200`，超限拒绝入队并提示先同步；设置页显示 `n / 200 条` |

### 10.2 实现要点

- 队列操作类型新增 `health.medication.checkin`、`investment.forex.create`。
- **用药打卡**：详情页此前只有只读展示，本轮新增「打卡」按钮；打卡 = `PUT /health/medication/{id}` 全量提交（`id` 已存在，PUT 天然幂等，无需查重）。
  - 离线时先用 `copyWith` 乐观更新并立即写队列，Snackbar「已打卡（待同步），联网后自动同步」；标题行出现「待同步」chip。
  - 列表行按队列 payload 覆盖 `taken_*` 计算「今日 x/3」，并显示「待同步」。
  - 列表进入详情时通过 `extra` 带记录快照（`initial`），**断网也能进入详情并打卡**（此前断网进入详情只有连接失败页）。
- **外汇录入**：`enqueueForexCreate(payload)`；列表从队列派生「待同步 N 笔」临时卡，放在 `ListStatusView` 之前，离线/加载失败时也能看到临时记录；
  `lastSyncAt` 前进触发刷新 → 队列条目消失、服务端真实记录补上，不会同时出现两条。
- **退避**：`retryDelays = 1s / 5s / 30s / 2min`；失败后 `retryCount+1` 并定时重试，第 5 次失败后不再自动重试；
  UI 显示「下次自动重试：HH:mm」或「自动重试已达上限，请手动重试」；连通性恢复会取消等待中的定时器并立即尝试。
- **上限**：`maxEntries = 200` 全局生效，`enqueue` 超限返回 null，三个入口（支出 / 用药 / 外汇）都提示「待同步已达上限（200 条），请先联网同步」。

### 10.3 重复风险评估（后端仍无幂等键）

- **用药打卡**：按 `id` PUT，重复执行结果一致，**不需要查重**；真实风险是「最后写入覆盖」——离线 payload 是打卡当时的本地快照，重试时可能覆盖其他端在同期更新的其他餐次。
  若将来记录被服务端删除，404 会一直留在队列直到重试耗尽转手动；建议查重/幂等键：`药物 id + record_date + 时段`（本轮因 PUT 幂等未加）。
- **外汇录入**：沿用 C1 补偿查重，`retryCount > 0` 时先查 `trade_date + symbol + order_type + open_price + lot_size + close_price + pnl + commission + overnight_fee + note`。
  - 同日同品种同方向同价同量同盈亏的两笔真实交易，第二笔重试时会被误判「已写入」而**漏写**；
  - 查重窗口受列表 `page_size=100` 限制，当日超过 100 条时可能查不到而重复；
  - 首次推送「已写入但响应超时」后重试有查重兜住。

### 10.4 真机实测（2026-11-07）

设备：Android 真机（`com.lifeos.mobile` debug APK），后端 `192.168.8.103:9515`（真实 MySQL）。
基线：用药总数 **472**、外汇交易总数 **4277**。

**用药打卡链路**

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 在线打开用药列表（测试记录 `C2MED`，`record_date=2026-11-07`，id=483），断网后进入详情 | 列表快照兜底生效：连接失败横幅 + 三餐用量仍可操作 |
| 2 | 点早餐「打卡」 | 详情「未完成」+「待同步」，早餐显示「已服」；Snackbar「已打卡（待同步），联网后自动同步」 |
| 3 | 返回列表 | `C2MED` 行显示「待同步」+ 今日 `1/3`、早餐 `1/1` |
| 4 | 杀进程冷启动（仍断网） | 设置页「待同步 **1 / 200 条**」，队列跨冷启动存活 |
| 5 | 恢复网络 | 自动推送成功，设置页 `0 / 200`，上次同步 05:39 |
| 6 | 服务端对账 | id=483 `taken_breakfast=true`、`updated_at=2026-11-07 05:39:01`；总数仍 **473**（PUT 更新，无新增、无重复），列表 `1/3` 且无「待同步」角标 |

**外汇录入链路**

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 在线进入外汇页（总数 4277），断网进入「新增交易」，填 `C2FX` / 做多 / 0.10 手 / 开 1.0850 / 平 1.0900 / 手续费 5 / 隔夜费 2 / 盈亏 50 | — |
| 2 | 保存 | 返回列表顶部出现「待同步 **1 笔**」卡（`C2FX` 做多 2026-11-07 · 0.10 手 · 开 1.0850 · 平 1.0900 · **¥57.00**）+ Snackbar「交易已存本地，联网后自动同步」 |
| 3 | 杀进程冷启动离线 → 投资 → 外汇 | 连接失败横幅下**仍显示待同步卡**，本地临时记录可见 |
| 4 | 恢复网络 | 自动推送成功，待同步卡消失；在线刷新后「交易记录 共 **4278** 笔」，首行 `C2FX` ¥57.00，**无「待同步」重复行** |
| 5 | 服务端对账 | `GET /investment/forex` total=**4278**，`C2FX` 仅 1 条（id=10315） |

截图（`docs/移动端可行性研究/screenshots/`）：

- `p3_c2_med_detail_offline.png`：断网打卡后的详情（已服 + 待同步）
- `p3_c2_med_list_offline.png`：断网返回列表后的「待同步」与 `1/3`
- `p3_c2_settings_coldstart.png`：冷启动后设置页 `1 / 200 条`
- `p3_c2_forex_pending_offline.png`：离线保存后的待同步卡（¥57.00）
- `p3_c2_forex_pushed.png`：推送成功后交易记录首行 `C2FX`，总数 4278

### 10.5 遗留测试数据（本轮未清理）

按要求本轮**不操作真实库**，以下测试数据保留待安排删除：

| 表 | 记录 | 基线 → 当前 |
|---|---|---|
| 用药记录 `health/medication` | id=**483**，`medicine_name=C2MED`，`record_date=2026-11-07`，`taken_breakfast=true` | 472 → **473** |
| 外汇交易 `investment/forex` | id=**10315**，`symbol=C2FX`，`trade_date=2026-11-07`，`pnl=50` / `commission=5` / `overnight_fee=2` | 4277 → **4278** |

### 10.6 涉及文件（C2）

| 文件 | 变更 |
|---|---|
| `lib/core/queue/outbox_entry.dart` | 新增 `health.medication.checkin` / `investment.forex.create` 常量 |
| `lib/core/queue/outbox_controller.dart` | 退避定时器、200 条上限、三类操作推送、外汇查重、`pendingOf` / `pendingPayloadFor` |
| `lib/core/models/health_models.dart` | `MedicationRecord.copyWith` |
| `lib/features/health/health_medication_detail_page.dart` | 「打卡」按钮、乐观更新、待同步 chip、离线快照兜底 |
| `lib/features/health/health_medication_page.dart` | 待同步状态覆盖、进入详情带快照 |
| `lib/features/invest/forex_create_page.dart` | 改为入队保存、离线横幅、上限提示 |
| `lib/features/invest/forex_page.dart` | 待同步交易卡、退避提示、同步后刷新 |
| `lib/features/finance/finance_transactions_page.dart` | 退避提示与「下次自动重试」 |
| `lib/features/finance/finance_expense_create_page.dart` | 上限提示 |
| `lib/features/settings/settings_page.dart` | `n / 200 条`、自动重试停止提示 |
| `lib/core/router/app_router.dart` | 用药详情路由支持 `extra` 快照 |
