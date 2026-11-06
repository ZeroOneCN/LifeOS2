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

## B4 物品追踪 / 卡片管理（已完成）

### 页面与接口
| 页面 | 路由 | 接口 |
|---|---|---|
| 物品追踪 | `/lifestyle/items` | `GET /lifestyle/items?page=&page_size=20`、`GET /lifestyle/items/stats?days=30` |
| 卡片管理 | `/lifestyle/cards` | `GET /lifestyle/bank-cards?page=&page_size=20`、`GET /lifestyle/bank-cards/stats?days=30` |

### 验收（真机 fe990217，375dp + 1.3x）
| 项 | 结果 |
|---|---|
| 物品追踪 | 426 件 / 使用中 374 / 总价值 ¥8,492.08 / 日均成本 ¥0.14 / 临期 0 / 已过期 0；状态分布 使用中 374、已回收 52；列表分页「加载更多」由 20 条追加到 40 条（`screenshots/p3_b4_items.png`） |
| 卡片管理 | 银行卡 20 张 / 正常 19 / 余额合计 ¥0.00 / 信用额度 ¥0.00 / 借记卡 19 / 信用卡 1；列表卡号只显示后四位（`screenshots/p3_b4_cards.png`） |
| 四态 | 有数据、加载、空态（EmptyState）、失败 + 重试均接；断网进入显示「连接失败，已保留登录状态」+ 重试，恢复网络点击后回到数据态（`screenshots/p3_b4_items_offline.png`） |
| 375 + 1.3x | 六项汇总、余额/额度、脱敏卡号均单行不换行；物品与卡片的元信息用 `Wrap` 换行，无省略截断、无横向滚动 |
| 返回 | 两页 AppBar 与系统返回正常，返回后生活 Tab 栈位置保留 |

### 卡号脱敏（安全底线）
- 模型 `BankCard` 保存原始 `card_number`，界面只允许使用 `maskedNumber`：去掉非数字字符后仅保留后四位，输出固定为 `•••• 1623`；空值显示「未填卡号」。
- 实测 20 张卡在列表里均只出现 `•••• xxxx`，没有任何完整卡号；模型不提供卡号字符串输出，也不写日志。
- 手机号卡（若后续接入）同样按「只留后四位」处理，不得完整展示。

### 到期日与临期判定（物品）
- `expire_date` 为空或无法解析时 `expiryInfo()` 返回 `null`，界面不显示任何临期/过期标记，也不计入「临期 / 已过期」。
- 有到期日时按本地自然日差计算：`daysLeft < 0` 显示红色「已过期 N 天」，`= 0` 显示「今天到期」，`1–30` 显示橙色「还剩 N 天」，`> 30` 不显示提示。
- 实测 426 件物品的 `expire_date` 全为空，因此页面临期 / 过期均为 0，符合「未填不判过期」的口径。

### 取舍说明
- 网页 `cards.tsx` 还包含「手机号卡」区块（生活中心入口显示「在册 29 张」= 银行卡 20 + 手机号卡 9）。本轮只做银行卡只读列表：手机号卡的充值、扣费、校准都是写操作，本轮不做，页内「共 20 张」与入口 29 张的差额即为手机号卡，未硬塞进页面。

## B5 外汇交易（已完成，整行大卡位置保持不动）

### 页面与接口
| 页面 | 路由 | 接口 |
|---|---|---|
| 外汇交易 | `/invest/forex` | `GET /investment/funds/stats`、`GET /investment/funds?page=&page_size=20`、`GET /investment/forex?page=&page_size=20` |
| 新增交易 | `/invest/forex/new` | `POST /investment/forex`（201，字段对齐网页端 `tradeFields`） |

### 资金动态区
- 四卡为正文大号数值（24 / `text-2xl` 级）+ 等宽数字，不用标签或徽章载体：累计出金、累计入金、体验金、净投入（口径 `net = 入金 - 出金 + 体验金`，与网页一致）。
- 明细每条一行四段：类型（出金/入金/体验金）· 金额（右对齐，定宽 78）· 日期（定宽 70）· 单号（`#id · 备注`，占剩余宽度，超长省略并用 Tooltip 给完整值）。
- 四卡与明细同处一张「资金动态」卡片，行高 7+7，没有大片空白；明细同样支持「加载更多」。

### 交易录入
- 从投资根页「外汇交易」整行大卡进入列表，右下角 `新增交易` 进入表单。
- 字段：交易日期、品种、方向（做多/做空）、手数、开仓价、平仓价、开仓时间、平仓时间、手续费、隔夜费、盈亏金额、备注；按「基础信息 / 价格与时间 / 费用与盈亏 / 备注」四组分区，375 下不横向滚动。
- 提交成功后返回列表并重新拉取资金合计、明细第一页、交易第一页；提交失败时**保留表单内容**、页内展示错误与「重试」，不丢数据（离线排队留批次 C）。

### 验收（真机 fe990217，375dp + 1.3x）
| 项 | 结果 |
|---|---|
| 四卡实测 | 累计出金 ¥3,242.76 / 累计入金 ¥6,033.40 / 体验金 -¥70.00 / 净投入 ¥2,720.64，资金明细 70 笔（`screenshots/p3_b5_forex.png`） |
| 交易列表 | 共 4277 笔，每页 20，「加载更多」由 20 条追加到 40 条；行内品种 + 方向 + 时间/手数/开平仓价，右侧净盈亏（`screenshots/p3_b5_trades_small.png`） |
| 盈亏配色 | 正收益 `success` 绿、负收益 `danger` 红、0/未平仓中性灰；负收益不使用 success 色 |
| 录入链路 | 新增 TESTB5 / 做多 / 0.10 手 / 开 1.0800 / 平 1.0900 / 盈亏 100 / 备注 `mobile-b5-verify` → 201 写入；返回列表后共 **4278** 笔，首行 TESTB5 显示绿色 ¥100.00；资金四卡数值不变（资金记录与交易记录独立），交易笔数与列表同步（`screenshots/p3_b5_saved.png`、`p3_b5_create.png`） |
| 四态 | 断网进入显示「连接失败，已保留登录状态」+ 重试，恢复网络点击后回到数据态（`screenshots/p3_b5_offline.png`） |
| 375 + 1.3x | 四卡 `FittedBox` 单行不换行；明细四段各自定宽/省略；交易元信息用 `Wrap` 换行；无横向滚动 |
| 返回 | AppBar 与系统返回正常，返回后投资 Tab 栈位置保留 |

### 取舍与遗留
- 写操作只做在线提交；提交失败重试结构已实现，但本轮未做「断网提交」实测（离线队列按约定留批次 C）。
- 验证用的 TESTB5 交易（备注 `mobile-b5-verify`）留在数据库，会参与盈亏/胜率统计；可在网页端外汇交易列表删除。
- 资金明细中出金金额沿用网页端「正数即绿色」口径（与明细类型色无强绑定），未额外改造。

## B6 财务/健康/生活/投资报告（待做）
