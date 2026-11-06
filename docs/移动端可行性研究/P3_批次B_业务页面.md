# P3 批次 B：业务列表页与明细页验收记录

> 数据源：后端 9515 真实接口；每域一提交、一验收。
> 通用要求：四态（加载 / 空 / 失败 / 有数据）、金额等宽数字、335 逻辑宽（375 屏×dp）与 1.3 倍字号不溢出、可返回。

---

## B1 账单管理 / 债务管理（已完成）

### 页面与接口
| 页面 | 路由 | 接口 |
|---|---|---|
| 账单管理 | `/finance/bills` | `GET /finance/loan-bills/stats?days=0`、`GET /finance/loan-bills?page=&page_size=20`、`GET /finance/loan-platforms?page_size=100` |
| 账单明细 | `/finance/bills/:id?platform=` | `GET /finance/loan-bills/{id}`、`GET /finance/repayments?bill_id={id}` |
| 债务管理 | `/finance/debts` | `GET /finance/debts/stats?days=0`、`GET /finance/debts?page=&page_size=20` |
| 债务明细 | `/finance/debts/:id` | `GET /finance/debts/{id}`、`GET /finance/debts/{id}/payments` |

### 验收
| 项 | 结果 |
|---|---|
| 有数据 | 账单：待还 ¥48,820.33 / 已还 ¥652,207.31 / 利息 ¥11,245.54；即将到期 7 条；全部 347 条分页（`screenshots/p3_b1_bills_list.png`） |
| 明细 | 字段 + 还款记录空态（`screenshots/p3_b1_bill_detail.png`） |
| 债务列表 | 共 26 笔，借入 ¥213,094.43 / 借出 ¥0.00 / 未还 ¥199,308.26（`screenshots/p3_b1_debts_list.png`） |
| 债务明细 | 名称/方向/对方/日期/本金/未还/利息/渠道 + 还款记录空态 |
| 加载态 | 首次进入显示居中转圈 |
| 失败态 | 断网进入债务页：「连接失败，已保留登录状态 / 连接超时」+ 重试（`screenshots/p3_b1_debts_offline.png`）；恢复网络点重试即出数据 |
| 空态 | 列表为空显示 EmptyState（明细还款 0 笔已实测） |
| 1.3x 字号 | 账单页汇总三列与列表标签均无溢出 |
| 返回 | AppBar 返回、系统返回均正常；分布页为 push 路由 |

### 实现说明
- 每页并行拉汇总 + 第一页（+ 平台名），`Future.wait`，任一失败整体进入失败态并保留旧数据。
- 首屏请求放在 `addPostFrameCallback`：`initState` 内不允许 `AppScope.of(context)`，否则 `dependOnInheritedWidgetOfExactType` 抛未处理异常、页面卡在加载态（本轮实测踩到并修复）。
- 平台 id → 名称一次拉取映射；明细页通过查询参数透传平台名，省一次请求。
- 金额统一 `formatMoney` + `FontFeature.tabularFigures()`。

---

## B2 步数统计 / 用药跟踪（已完成）

### 页面与接口
| 页面 | 路由 | 接口 |
|---|---|---|
| 步数统计 | `/health/steps` | `GET /health/steps/stats?days=7\|30\|90` |
| 用药跟踪 | `/health/medication` | `GET /health/medication/stats?days=7`、`GET /health/medication?page=`、`GET /health/medication/stocks` |
| 用药明细 | `/health/medication/:id` | `GET /health/medication/{id}` |

### 验收
| 项 | 结果 |
|---|---|
| 步数统计 | 30 天：总步数 122,498 / 日均 4,224 / 最高 12,352 / 493 条；近 14 天柱状图（最高柱实心）；分时段累计 08-09…18-19；每日明细含距离与热量（`screenshots/p3_b2_steps.png`） |
| 区间切换 | 7 / 30 / 90 天 SegmentedButton 可切换并重新取数 |
| 用药跟踪 | 今日 0 已服 / 0 待服 / 7 日依从率 100%；早 0/0、午 1/1、晚 2/2；库存 1 项（余量 20 粒、预警 2 粒、约 14 天）；用药记录 472 条分页（`screenshots/p3_b2_medication.png`） |
| 用药明细 | 药名/日期/总用量 + 三餐用量与已服状态（`screenshots/p3_b2_medication_detail.png`） |
| 四态 | 加载、失败（同 B1 的 ListStatusView）、空态、有数据均接；步数空区间显示 EmptyState |
| 1.3x | 汇总三列与分时段行无溢出 |
| 返回 | AppBar 与系统返回均正常 |

### 实现说明
- 步数不单独做分页接口：统计接口的 `trend` 已含每日明细，直接取最近 14 天渲染，避免重复请求。
- 柱状图用 `Row + Expanded + Container` 等比高度实现，未引入图表库（数据量小、只表达趋势）。
- 用药记录一行代表一天（早/午/晚粒数与已服标记），明细页只做字段展示，写操作留给批次 C 的离线队列。

---

## B3 购物记录 / 旅行开支 / 财务规划（已完成）

### 页面与接口
| 页面 | 路由 | 接口 |
|---|---|---|
| 购物记录 | `/finance/shopping` | `GET /finance/shopping/records?page=&page_size=20`、`GET /finance/shopping/records/stats?days=3650`、`GET /finance/shopping/platforms?page_size=100`、`GET /finance/shopping/categories` |
| 旅行开支 | `/finance/travel` | `GET /finance/travel/ledgers?page_size=100`、`GET /finance/travel/details?page=&page_size=20[&ledger_id=]`、`GET /finance/travel/details/stats?days=3650[&ledger_id=]` |
| 财务规划 | `/finance/planning` | `GET /finance/planning?page=&page_size=20`、`GET /finance/planning/stats?days=0` |

### 验收（真机 fe990217，375dp + 1.3x）
| 项 | 结果 |
|---|---|
| 购物记录 | 总额 ¥8,492.08 / 426 笔 / 平均单笔 ¥19.93 / 4 个平台；按平台 拼多多 ¥5,708.79、京东 ¥1,905.68、淘宝 ¥846.61、唯品会 ¥31.00；分页「加载更多」由 20 条追加到 40 条（`screenshots/p3_b3_shopping.png`） |
| 旅行开支 | 实付 ¥2,566.86 / 原价 ¥2,805.89 / 优惠 ¥239.03 / 50 笔；按分类 交通 ¥2,347.45、餐饮 ¥140.63、住宿 ¥50.00、购物 ¥28.78（金额为 0 的分类不展示）；行程下拉含 2 个账本，切换后按 `ledger_id` 重新取数（`screenshots/p3_b3_travel.png`） |
| 财务规划 | 目标 ¥200,000.00 / 已存 ¥0.00 / 完成率 0.0%；规划 1 条（购车计划，进行中）；`days=30` 会漏掉 2026-09-10 的历史规划，故统计用 `days=0` 全量（`screenshots/p3_b3_planning.png`） |
| 四态 | 有数据、加载、空态（EmptyState）、失败 + 重试均接；断网进入显示「连接失败，已保留登录状态」+ 重试，恢复网络点击后回到数据态（`screenshots/p3_b3_shopping_offline.png`） |
| 375 + 1.3x | 三列汇总、聚合金额、规划进度条与「已存/目标」均单行不换行；列表元信息改为 `Wrap` 换行显示，避免省略号截断 |
| 返回 | 三页 AppBar 与系统返回均正常，返回后财务 Tab 栈位置保留 |

### 实现说明
- 三页只做只读列表，不新增明细页：购物与旅行后端没有单条 GET，规划明细在移动端也没有更多可展示字段；写操作留给批次 C。
- 旅行与规划的聚合卡过滤金额为 0 的项，避免窄屏出现成排「¥0.00」。
- 新增公共 `AmountBreakdownList` 与 `ListLoadMoreFooter`（`finance_status_widgets.dart`），三页复用，未新造卡片规范。
- 商品/项目标题保留 2 行省略（超长电商标题无法在 375 宽完整展示），日期、平台/分类、时长的元信息不截断。

---

## B4 物品追踪 / 卡片管理（待做）

## B5 外汇交易（待做，整行大卡位置保持不动）

## B6 财务/健康/生活/投资报告（待做）
