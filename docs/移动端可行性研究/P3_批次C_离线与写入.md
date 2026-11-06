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
| 自动退避 | 完成 | 1s / 5s / 30s / 2min，第 5 次失败后停止自动重试转手动；实测间隔符合预期（见 10.4） |
| 队列上限 | 完成 | `maxEntries = 200`，超限拒绝入队并提示先同步；200 条下第 201 条被拒、既有 200 条完好（见 10.4） |

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
- `p3_c2_retry_exhausted.png`：退避耗尽后的「自动重试已达上限，请手动重试」
- `p3_c2_cap_rejected.png`：队列满 200 条时第 201 条被拒并保留表单

### 10.4.1 退避时序实测（服务器地址 `192.168.8.199:9515`，不可达）

通过 `run-as` 轮询 `shared_prefs/FlutterSharedPreferences.xml` 中的 `retry_count`，记录每次失败时刻：

| 事件 | 相对保存时刻 | 间隔（含 HTTP 尝试约 2–3s） |
|---|---|---|
| 入队（retry=0） | 5.5s | — |
| 第 1 次失败（retry=1） | 8.7s | 3.2s ≈ 1s 退避 + 尝试 |
| 第 2 次失败（retry=2） | 11.9s | 3.2s ≈ 1s 退避 + 尝试 |
| 第 3 次失败（retry=3） | 20.1s | 8.2s ≈ 5s 退避 + 尝试 |
| 第 4 次失败（retry=4） | 53.0s | 32.9s ≈ 30s 退避 + 尝试 |
| 第 5 次失败（retry=5） | 176.4s | 123.4s ≈ 2min 退避 + 尝试 |

- 第 5 次失败后再等待 70s，`retry_count` 保持 5，**未再自动重试**；流水页显示「自动重试已达上限，请手动重试」。
- 恢复地址 `192.168.8.103:9515` 后点「立即同步」：队列清空（`[]`）、`last_sync_at=06:07:15`，服务端出现该笔支出。
- 实测间隔与代码中的 1s/5s/30s/2min 一致（差值来自每次不可达地址的 TCP 尝试耗时）。

### 10.4.2 队列上限实测

为不污染真实库，在断网状态下通过 `run-as` 预置 200 条 `finance.shopping.create` 占位条目（`cap-0001`…`cap-0200`）：

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 冷启动后设置页 | 「离线队列 / 待同步 **200 / 200 条**」 |
| 2 | 再记一笔（`CAP-OVERFLOW` ¥9.99）并保存 | SnackBar「**待同步已达上限（200 条），请先联网同步后再记一笔**」；**停留在表单**，金额/说明保留 |
| 3 | 读偏好文件校验 | `local_id` 仍 200 条，`cap-0001`/`cap-0200` 均在，`CAP-OVERFLOW` 未写入 |
| 4 | 停应用后把队列写回 `[]`，启动复查 | 设置页 **0 / 200 条**，应用正常 |

### 10.5 测试数据清理（本轮已完成）

| 表 | 记录 | 删除方式 | 结果 |
|---|---|---|---|
| 用药 `health/medication` | id=**483**（`C2MED`，2026-11-07） | `DELETE /health/medication/483`（与网页端删除用药同一接口） | 成功；总数回到 **472**；今日统计 `taken_count=0`、`items=[]` |
| 外汇 `investment/forex` | id=**10315**（`C2FX`，2026-11-07） | `DELETE /investment/forex/10315` | 成功；总数回到 **4277**；`C2FX` 已不存在 |
| 支出 `finance/shopping/records` | id=**437**（`C2-RETRY` ¥9.99，退避测试推送成功后的记录） | `DELETE /finance/shopping/records/437` | 成功；今日 **0** 条，总数 **426** |

全程只用官方 HTTP 接口删除，未使用 SQL 直接改库。

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

---

## 十一、C3 补口：通知中心页 + 手机号卡只读区（2026-11-07 06:1x–06:4x）

> 范围：只改 `mobile/`。两块互不相干的补口：
> 1）顶栏铃铛从「假未读 3」换成真实通知中心；
> 2）卡片管理页补齐入口写着 29 张、实际只显示 20 张银行卡的差额（9 张手机号卡，只读）。

### 11.1 后端能力核对（未新增接口）

| 能力 | 接口 | 结论 |
|---|---|---|
| 通知列表 | `GET /notifications?page=&page_size=` | 存在（page_size ≤ 100，默认 notify_date desc） |
| 未读/总数概览 | `GET /notifications/stats?days=` | 存在（total / unread / today / by_category / trend，days ≤ 365） |
| 单条标记已读 | `PUT /notifications/{id}` | 存在；schema 为全量 `NotificationCreate`（title / category / notify_date 必填） |
| 全部标记已读 | `POST /notifications/read-all` | 存在 |
| 手机号卡列表 | `GET /lifestyle/phone-cards?page=&page_size=` | 存在（`PhoneCardRead` 含运营商/套餐/账期/余额，另有 month_charged 等派生字段） |

没有造接口；手机号卡的充值 / 扣费 / 校准本轮一律不做。

### 11.2 通知中心

- 入口：`RootPageScaffold` 固定铃铛 → `/notifications`；角标取 `stats?days=365` 的 `unread`。
- 列表项：未读圆点 + 加粗标题、`category` chip、`来源 xxx`、`notify_date`；收起时正文摘要 2 行，点击展开完整正文（保留换行）并显示备注。
- 标题 `maxLines: 1` + `Tooltip(message: title)`；展开后正文不截断。
- 未读项点击即标记已读（`PUT /notifications/{id}`，回写列表快照的全量字段）；行内 spinner 防重复点击。
- 「全部标记已读」：先弹确认框（「将把 N 条未读通知标记为已读」）再 `POST /notifications/read-all`。
- 分页：首屏 20 条 + 底部「加载更多」，`hasMore` 由 `items.length < total` 决定。
- 四态：加载 / 空（`EmptyState`）/ 失败（保留登录态显示「连接失败 + 重试」）/ 有数据。

**取舍：标记已读不接离线队列。** 已读状态滞后不致命，失败只需提示重试；接入队列会占用 200 条额度、并让「未读数」在离线时与服务端不一致，收益极低。

### 11.3 手机号卡只读区

- 与银行卡同页：银行卡区标题由「全部卡片」改为「银行卡」（`共 20 张`），手机号卡独立 `SectionCard`（`共 9 张 · 只读`）。
- 顶部固定提示：`只读：充值 / 扣费 / 校准请在网页端操作`；空态同样用这句话，避免被误认为加载失败。
- 每行：脱敏号码（`•••• 6417`，只留后四位）、运营商、套餐、账期（`每月 X 日` + `月租 ¥N`）、余额、非 active 状态（已冻结/已过期/已停用）。
- 手机号卡请求单独 `catchError`：失败只让该区块降级为空态，不阻塞银行卡分页。
- 套餐文案修正：后端未配置的通话/短信项存 `"0"`，直接拼接会出现 `0 · 30 · 0`；现跳过数值为 0 的项（`200MB/月` 这类带单位的仍保留）。

### 11.4 真机实测（基线：通知 86 条 / 未读 86；银行卡 20 + 手机号卡 9 = 29）

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 冷启动财务中心 | 铃铛红色角标 **86**；读屏标签「通知（86 条未读）」 |
| 2 | 点铃铛 | 通知中心：`共 86 条`、`未读 86 条`、首屏 20 条 |
| 3 | 点首条（id=92，`finance_loan_due:574`） | 展开完整正文（含换行）；未读 **86 → 85**；行内圆点消失、标题取消加粗 |
| 4 | 服务端对账 | `GET /notifications/92` → `read=True`；`stats` unread=**85** |
| 5 | 滚到底点「加载更多」 | 追加第 2 页（新出现 `【网贷还款】白条 2026-10-23 应还`） |
| 6 | 点「全部标记已读」 | 弹窗「将把 **85** 条未读通知标记为已读，是否继续？」；点「取消」后未读仍 85（未执行批量写） |
| 7 | 断网点未读项（id=91） | SnackBar「标记已读失败：无法连接服务器，请检查地址、端口与局域网，请重试」；未读保持 85，id=91 仍 `read=False`（未进队列） |
| 8 | 断网进入通知中心 | 「连接失败，已保留登录状态」+「重试」；恢复网络点重试 → `共 86 条 / 未读 85` |
| 9 | 375 宽（1125×2670）与 1.3x 字体 | 不溢出；标题省略号截断（`Tooltip` 提供全文），元信息自动换行 |
| 10 | 卡片管理 | 银行卡 `共 20 张`；手机号卡 `共 9 张 · 只读`，9 行全展示（`•••• 6417` 中国移动 / 每月 4 日 · 月租 ¥8.00 / 余额 ¥23.30 等） |
| 11 | 375 + 1.3x（卡片管理） | 不溢出，手机号卡行两行内换行正常 |

截图（`docs/移动端可行性研究/screenshots/`）：`p3_c3_bell_badge.png`、`p3_c3_notification_list.png`、
`p3_c3_notification_expanded_read.png`、`p3_c3_read_all_dialog.png`、`p3_c3_mark_read_offline_failed.png`、
`p3_c3_notification_failed_retry.png`、`p3_c3_notifications_375.png`、`p3_c3_notifications_font13.png`、
`p3_c3_phone_cards_section.png`、`p3_c3_phone_cards_list.png`、`p3_c3_phone_cards_375.png`、`p3_c3_phone_cards_font13.png`。

### 11.5 真实库测试数据（**未清理，等用户决定**）

| 记录 | 变更 | 说明 |
|---|---|---|
| 通知 id=**92**（`finance_loan_due:574`） | `read` 由 `False` → `True` | 单条标记已读实测产生；其余 85 条未读未改动 |

批量「全部标记已读」只验证了确认框并取消，**没有**对真实库执行；`mark_read_offline_failed` 的失败请求也未落库（id=91 仍未读）。

### 11.6 遇到的问题

- **铃铛冷启动读不到未读数**：首帧 `postFrameCallback` 早于 `AuthService.restore()` 完成，`isLoggedIn` 仍为 false 直接 return，角标一直是 0。改为订阅 `AuthService`，恢复成功后补拉；登出清 0。
- **读屏把按钮播报成「86」**：`Badge` 的数字语义覆盖了 tooltip。给角标包 `ExcludeSemantics`，标签恢复「通知（85 条未读）」。
- 单条已读必须回写全量字段（后端 PUT 走 `NotificationCreate`），因此用列表快照；若其他端同时改了同一条正文，会被列表快照覆盖（低频，可接受）。
- 手机号卡一次性 `page_size=100`，当前 9 张够用；超过 100 张需要补分页。

### 11.7 涉及文件（C3）

| 文件 | 变更 |
|---|---|
| `lib/core/models/notification_models.dart` | 新增 `AppNotification`（summary / copyWith / fromJson） |
| `lib/features/notifications/notification_center_page.dart` | 新增通知中心（分页、四态、展开、单条已读、全部已读确认） |
| `lib/shared/widgets/notification_bell.dart` | 假未读 3 → 真实 `stats` 未读数；订阅登录态；返回后刷新；角标语义修正 |
| `lib/core/router/app_router.dart` | `/notifications` 由占位页改为 `NotificationCenterPage` |
| `lib/core/models/lifestyle_models.dart` | 新增 `PhoneCard`（脱敏号码 / 套餐 / 状态） |
| `lib/features/life/lifestyle_cards_page.dart` | 银行卡区标题改「银行卡」；新增手机号卡只读区与 `_PhoneCardRow`；手机号卡失败降级 |
---

## 十二、C4：设置子页补齐 + 入口完整性核查（2026-11-07 06:5x–07:1x）

### 12.0 第 0 步：还原上一轮的通知已读状态

`PUT /notifications/92` 回写 `read=false`（全量字段 title/content/category/source/notify_date/note），
`GET /notifications/92` → `read=False`，`GET /notifications/stats?days=365` → `unread=86`，与上轮基线一致。

### 12.1 账户设置（`/settings/account`）

后端能力核对：`GET /user/profile`、`PUT /user/profile`（nickname/email/phone/signature 等）、
`GET /user/settings`（account、has_password）、`PUT /user/settings`（current_password + new_password）均存在，未造接口。

- 基本资料：昵称（必填、≤20）、邮箱（轻量正则）、手机号、个性签名（≤60）；保存 `PUT /user/profile` 后调用
  `AuthService.refreshProfile()`，设置页账户卡昵称立即刷新（实测 成春炫 → LifeOSQA → 返回设置页显示 LifeOSQA）。
- 登录密码：已有密码时显示「当前密码」；新密码 ≥ 6 位且两次一致；`PUT /user/settings` 成功清空输入并提示。
- 写操作直接打接口、不进离线队列：资料/密码即时生效，失败提示重试即可。
- 375 与 1.3x：表单不溢出（截图 `p3_c4_account_*`）。
- 实测密码错误路径：当前密码填 `wrongpass`、新密码 `abcdef` → 后端返回「当前密码错误」，界面提示
  「修改失败：当前密码错误」，**未改任何密码**（后端先校验再落库）。

### 12.2 外观（浅色 / 深色 / 跟随系统）

- `PreferencesService` 新增 `ui.theme_mode` 键与 `ValueNotifier<ThemeMode>`；`LifeOsApp` 用 `ValueListenableBuilder`
  监听它，切换立即重建全部页面。
- 只提供 `ThemeMode` 三态（light/dark/system），不做「跟随系统 + 记住上次手动选择」这类 Flutter 做不到的组合。
- 实测：切深色立即生效 → 冷启动（force-stop 后重启）仍为深色 → 切回跟随系统恢复浅色（系统当前为浅色）。
- 冷启动恢复读取发生在 `runApp` 之前，无闪白/闪黑。
- 截图：`p3_c4_settings_theme_dark.png`、`p3_c4_settings_theme_persist.png`、`p3_c4_settings_375_font13.png`。

### 12.3 关于（`/settings/about`）

- 应用名、版本号、包名来自 `package_info_plus`（即构建时的 `pubspec.yaml` 版本，实测 `1.0.0+1`），不写死；
  新增依赖 `package_info_plus`。
- 后端地址读取 `ApiClient.baseUrlListenable`，切换服务器地址后无需重启即更新；长 URL 与包名独占一行，375 + 1.3x 不折断。
- **不放「检查更新」按钮**：后端没有版本/更新检查接口，页面上明确写出原因，不放假按钮。
- 截图：`p3_c4_about.png`、`p3_c4_about_375_font13.png`。

### 12.4 入口完整性核查（以 `frontend/src/config/routes.ts` 为唯一真源）

| 网页端路由 | 移动端入口位置 | 状态 |
|---|---|---|
| `/home` | 无独立页；5 个 Tab 首屏 | 有意隐藏（既定：取消系统首页，内容拆入 Tab） |
| `/notifications` | 各 Tab 根页顶栏铃铛 → 通知中心 | 可达 |
| `/activity-logs` | 无 | 有意隐藏（管理员运维页，手机端不做） |
| `/login-audit` | 无 | 有意隐藏（同上） |
| `/sessions` | 无 | 有意隐藏（既定并入「设置→登录设备」，P3 未排期） |
| `/backup` | 无 | 有意隐藏（管理员导出类，破坏性强） |
| `/system-settings` | 无 | 有意隐藏（手机端仅只读，改配置回桌面） |
| `/health/overview` | 健康 Tab 根页 | 可达 |
| `/health/vitals-sleep` | 健康页「睡眠体征」 | 可达（占位页） |
| `/health/fitness` | 健康页「健身运动」 | 可达（占位页） |
| `/health/steps` | 健康页「步数统计」 | 可达 |
| `/health/checkup` | 健康页「体检指标」 | 可达（占位页） |
| `/health/medication` | 健康页「用药跟踪」（含详情） | 可达 |
| `/health/reports` | 健康页「健康报告」（含详情） | 可达 |
| `/finance/overview` | 财务 Tab 根页 | 可达 |
| `/finance/shopping` | 财务页「购物记录」 | 可达 |
| `/finance/travel` | 财务页「旅行开支」 | 可达 |
| `/finance/bills` | 财务页「账单管理」（含详情） | 可达 |
| `/finance/planning` | 财务页「财务规划」 | 可达 |
| `/finance/debts` | 财务页「债务管理」（含详情） | 可达 |
| `/finance/reports` | 财务页「财务报告」（含详情） | 可达 |
| `/lifestyle/overview` | 生活 Tab 根页 | 可达 |
| `/lifestyle/items` | 生活页「物品追踪」 | 可达 |
| `/lifestyle/cards` | 生活页「卡片管理」 | 可达 |
| `/lifestyle/reports` | 生活页「生活报告」（含详情） | 可达 |
| `/investment/overview` | 投资 Tab 根页 | 可达 |
| `/investment/forex` | 投资页「外汇交易」（含录入） | 可达 |
| `/investment/reports` | 投资页「投资报告」（含详情） | 可达 |
| `/user-center` | 设置 Tab「账户设置」 | 可达 |
| `/user-center/settings` | 同账户设置（网页端重定向等价） | 可达 |

**结论：漏了 0 条。** 9 条未映射项中，`/home` 与 5 个管理员/系统页为既定隐藏，2 个健康页（睡眠/健身/体检）为可达占位。
移动端另有网页端路由表没有的入口（财务流水 `/finance/transactions`、支出录入 `/finance/expense/new`、
服务器地址 `/settings/server`、通知中心独立页 `/notifications`），属移动端增量，不在本轮核对范围。

### 12.5 真机实测与真实数据改动（均已还原，见 12.6）

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 设置页外观 | 三选一单选正常，深色即时生效 |
| 2 | 冷启动 | 深色保持（`ui.theme_mode` 持久化） |
| 3 | 账户设置 | 读到昵称/邮箱/手机/签名、账号 admin、has_password=true |
| 4 | 改昵称 → 保存 → 返回 | 提示「资料已保存」，设置页账户卡即时刷新 |
| 5 | 密码错误路径 | 「修改失败：当前密码错误」，密码未变 |
| 6 | 关于 | 版本 `1.0.0+1`、包名 `com.lifeos.mobile`、后端地址独占一行；无「检查更新」按钮 |
| 7 | 375 + 1.3x | 三个子页均不溢出 |

### 12.6 真实数据改动与还原（**最终均已还原**）

| 数据 | 改动 | 还原方式 | 还原后 |
|---|---|---|---|
| 通知 id=92 | 上轮 `read=true` | `PUT /notifications/92` read=false | unread=86 |
| 用户昵称 | 成春炫 → LifeOSQA（App 保存实测） | `PUT /user/profile` nickname=成春炫 | 成春炫（App 冷启动已确认） |
| 用户手机号 | 18316426417 → LifeOSQA（点击坐标误入手机号框） | `PUT /user/profile` phone=18316426417 | 18316426417 |
| 登录密码 | 未改（错误当前密码被后端拒绝） | — | 原密码不变 |
| 本地主题 | system → light → dark → system | 设置页点「跟随系统」 | 跟随系统 |
| 显示设置 | wm size 1125×2670 / font_scale 1.3 | `wm size reset` + `font_scale 1.0` | 默认 |

### 12.7 涉及文件（C4）

| 文件 | 变更 |
|---|---|
| `lib/core/storage/preferences_service.dart` | `ui.theme_mode` 持久化 + `ValueNotifier<ThemeMode>` |
| `lib/app.dart` / `lib/main.dart` | `MaterialApp.router` 接入主题 notifier |
| `lib/features/settings/settings_page.dart` | 外观三选一 RadioGroup；关于入口替换旧静态卡片 |
| `lib/features/settings/account_settings_page.dart` | 新增账户设置（资料表单 + 改密） |
| `lib/features/settings/about_page.dart` | 新增关于页（package_info_plus + 后端地址） |
| `lib/core/router/app_router.dart` | `/settings/account`、`/settings/about` 由占位换实页 |
| `pubspec.yaml` / `pubspec.lock` | 新增 `package_info_plus` |

---

## 十三、C5：健康域两个占位页（睡眠体征 / 健身运动）（2026-11-07 07:2x–07:4x）

> 范围：只改 `mobile/`；只做健康域两个占位页，**体检指标不开**。两页均为只读，不写入真实数据。

### 13.1 后端能力核对（未新增接口）

| 页面 | 接口 | 结论 |
|---|---|---|
| 睡眠体征 | `GET /health/vitals-sleep?page=&page_size=` | 存在；返回 `bedtime` / `wake_time` / `sleep_duration_min` / `deep_sleep_min` / `light_sleep_min` / `wake_count` / `sleep_quality` / `note` |
| 睡眠体征 | `GET /health/vitals-sleep/stats?days=0` | 存在；`avg` 含平均时长/深睡/质量，另有 `record_count` 与 `trend` |
| 健身运动 | `GET /health/fitness?page=&page_size=&start=` | 存在；默认按 `record_date` 倒序 |
| 健身运动 | `GET /health/fitness/stats?days=` | 存在；`total_count` / `total_minutes` / `total_calories` / `by_type` / `trend` |

**字段事实**：`HealthVitalsSleep` 没有 REM 字段（只有深睡/浅睡/醒来次数），因此睡眠页不展示 REM；
`HealthFitness.distance_km` 可为空，`calories` 在 MET 推算不到时也可为空。两页均只读，不做新增/编辑。

### 13.2 睡眠体征（`/health/vitals-sleep`）

- 概览：平均时长（接口均值 429.6 分钟，页面取整为「7 小时 10 分」）、平均质量（`2.2 / 10`）、记录条数 `24`。
- 分阶段：深睡 / 浅睡均值；接口当前全为 null → 展示「暂无分阶段数据」空态，并写明未采集字段显示「—」。
- 记录行：日期 + 时长（右侧等宽数字）+ 质量、入睡/起床时间、深睡/浅睡/醒来次数（用 `Wrap` 整项换行，避免 1.3x 时「—」单独掉行）。
- **未采集不显示 0**：`sleep_duration_min` / `deep_sleep_min` / `light_sleep_min` / `wake_count` / `sleep_quality` 为 null 时一律「—」；
  实测 2026-10-26 至 10-30 共 5 条空记录，列表 5 行全部为「—」，未出现 0 分钟 / 0 次 / 0 分。
- 分页：20 条/页 + 「加载更多」；24 条实测点一次追加 4 条，底部变「已加载全部」。
- 只读提示：页内固定 `ReadOnlyNotice`「当前版本仅支持查看，记录请在网页端添加。」，不放新增按钮。

### 13.3 健身运动（`/health/fitness`）

- 区间：7 天 / 30 天 / 全部（接口 `days` 原生能力，默认「全部」）；**列表与统计同区间**（`days>0` 时列表同时带 `start`），避免汇总显示 0 条而下方仍列出全部记录。
- 区间汇总：总时长（922 分钟 → 15 小时 22 分）、总消耗（4,881.2 kcal）、记录条数 10。
- 按类型汇总：仅「有氧运动」10 次 / 15 小时 22 分 / 4,881.2 kcal；区间无记录时该卡片不渲染，不硬造。
- 记录列表：按 `record_date` 倒序并插入日期分组标题；行内类型、时长、消耗（`840 kcal`），有 `distance_km` 才追加距离，备注原样展示。
- 未采集不显示 0：`calories` 为 null 时显示「— kcal」。
- 分页与四态同上；只读提示同上。

### 13.4 真机实测（基线：睡眠 24 条；健身 10 条 / 922 分钟 / 4,881.2 kcal）

| # | 步骤 | 结果 |
|---|---|---|
| 1 | 健康 Tab → 睡眠体征 | 平均时长 7 小时 10 分 / 平均质量 2.2 / 10 / 记录 24 条；分阶段空态 |
| 2 | 睡眠列表首屏 | 10-30…10-26 共 5 条全空记录全部「—」；07-19 起显示 9 小时 50 分、入睡 18:52、起床 04:42、质量 2/10 |
| 3 | 点「加载更多」 | 追加 4 条（07-04…07-01），底部「已加载全部」；5 小时 49 分 / 7 小时 11 分 / 6 小时 / 8 小时 55 分与接口一致 |
| 4 | 系统返回 | 回到健康中心 |
| 5 | 健身运动（全部） | 15 小时 22 分 / 4,881.2 / 10 条；按类型「有氧运动」10 次；列表按日期倒序 |
| 6 | 切「近 7 天」 | 汇总 0 分 / 0 / 0，列表同为空态（该区间无记录），无重复空态 |
| 7 | 375 宽 + 1.3x | 两页不溢出；睡眠分阶段字段按整项换行，健身汇总三列与分段按钮正常 |
| 8 | 断网进入两页 | 「连接失败，已保留登录状态 + 重试」；恢复网络点重试，数据恢复 |
| 9 | 可返回 | 两页系统返回均正常 |

截图：`p3_c5_sleep_overview.png`、`p3_c5_sleep_list.png`、`p3_c5_sleep_375_font13.png`、
`p3_c5_sleep_offline.png`、`p3_c5_fitness_overview.png`、`p3_c5_fitness_7d_empty.png`、
`p3_c5_fitness_375_font13.png`、`p3_c5_fitness_offline.png`。

### 13.5 真实数据改动

**无。** 本轮两页只发 `GET` 请求，未新增/修改/删除任何记录；真机自动化全程未点击任何输入框（本轮没有表单）。
显示设置（1125×2670 / font_scale 1.3）与 Wi-Fi 开关仅用于验收，已恢复默认（`wm size reset` + `font_scale 1.0`，Wi-Fi 已开启）。

### 13.6 遇到的问题

- **分阶段字段换行难看**：1.3x 下「深睡 — · 浅睡 — · 醒来 —」整段折行，最后的「—」单独掉到下一行。改为 `Wrap` 三个独立项，按项换行。
- **区间与列表范围不一致**：初版只让统计随区间变化，列表仍为全部，会出现「近 7 天 0 条」但下面列出 4 月记录。改为 `days>0` 时列表同时传 `start=今天-(days-1)`。
- **空态重复**：区间无记录时「按类型汇总」与「运动记录」各一个空态。无记录时不渲染按类型卡片，只保留列表空态。
- 其余复用既有规范（`ListStatusView` / `EmptyState` / `SectionCard` / `ListLoadMoreFooter` / `DetailPageScaffold`），未新造组件。

### 13.7 涉及文件（C5）

| 文件 | 变更 |
|---|---|
| `lib/core/models/health_models.dart` | 新增 `SleepRecord` / `SleepTrendPoint` / `SleepStats` / `FitnessRecord` / `FitnessTypeSummary` / `FitnessStats`；空值解析保持 null |
| `lib/core/utils/formatters.dart` | 新增 `formatDuration`（分钟 → 小时/分，null → 「—」）与 `formatOneDecimal` |
| `lib/shared/widgets/read_only_notice.dart` | 新增只读说明条（两页复用） |
| `lib/features/health/health_sleep_page.dart` | 新增睡眠体征页（概览 + 分阶段 + 分页记录 + 四态） |
| `lib/features/health/health_fitness_page.dart` | 新增健身运动页（区间汇总 + 按类型 + 日期倒序列表 + 四态） |
| `lib/core/router/app_router.dart` | `/health/vitals-sleep`、`/health/fitness` 由占位换实页（体检指标仍占位） |