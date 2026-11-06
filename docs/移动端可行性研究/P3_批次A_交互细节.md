# P3 批次 A：交互细节（A1–A4）进度报告

> 日期：2026-11-07　状态：**A1 / A2 / A3 / A4 全部完成并真机验证**
> 工程：`mobile/`（仅移动端；`frontend/`、`backend/` 未改动）
> 真机：`fe990217`（23127PN0CC / Android 16 / 1200×2670 / dpr 3.0）
> `flutter analyze`：**0 error / 0 warning**（提交前复跑）

---

## 0. 结论前置

| 项 | 结果 |
|---|---|
| A1 底部 Tab 只显示图标 | `NavigationDestinationLabelBehavior.alwaysHide`；选中态用 M3 实心胶囊 + 图标变色 |
| A1 长按出全称 | 五个 `NavigationDestination.tooltip` → 深色气泡；长按要求 400ms 出现，松手即隐，不切换 Tab |
| A1 一次性提示 | 首次启动 6 秒轻提示（非模态、可关、只出现一次，键 `ui.tab_long_press_hint_shown`） |
| A1 深色可辨 | 选中：亮色胶囊 + 高对比图标；未选中：暗灰图标（截图 `h1`） |
| A2 登录卡顿 | 实测后改为「先可见域、后其余三域」+ 每域独立 notifier，财务首屏 490ms → 160ms |
| A3 离线冷启动 | 区分「未登录 / 连接失败」；后者保留登录态 + 「重试」，不踢回登录页 |
| A4 头像 | `POST/PUT /user/avatar` + `GET /user/profile`；相册上传 / 填地址 / 移除三条路径真机走通 |

---

## 1. A1 底部 Tab 隐藏文字

### 实现
- `NavigationBar(labelBehavior: NavigationDestinationLabelBehavior.alwaysHide)`。
  选它而不是只隐藏 `label` 的原因：`alwaysHide` 是 M3 官方语义，可访问性树里仍保留标签文字，
  且长按 `Tooltip` 走框架树内气泡，无需自绘 Overlay。
- 五个 destination 全部带 `tooltip`：健康中心 / 财务中心 / 生活中心 / 投资中心 / 设置。
- `TooltipTheme` 包住 `NavigationBar`：`waitDuration 400ms`、`showDuration 350ms`、`exitDuration 80ms`，
  在 500ms 量级出、松手立刻收，且 `Tooltip` 只是长按手势包装，不拦截 Tab 的点击。
- 首次提示：`_TabHintBanner` 从 `PreferencesService.tabHintShown` 判断，只出现一次，
  6 秒自动消失、右上角可关，不弹模态、不阻塞操作。
- 每个 Tab 根页 `AppBar` 仍保留全称标题（P1 已有），隐藏文字不会造成识别困难。

### 真机验证
| 截图 | 验证点 |
|---|---|
| `screenshots/p3_a1_tabs_icons_only.png` | 五 Tab 仅图标；财务为实心胶囊选中态 |
| `screenshots/p3_a1_longpress_tooltip.png` | 长按健康中心 500ms 左右弹出「健康中心」气泡，当前 Tab 仍为设置，未误切换 |
| 松手后 | 气泡消失、仍停留设置页，未触发页面跳转 |
| `screenshots/p3_a1_dark_mode_selected.png` | 深色模式下选中为亮色胶囊 + 白色图标，未选中为暗灰，对比清晰 |

---

## 2. A2 登录卡顿与登录后卡顿

### 先量：debug 构建 + 局域网后端（9515）实测

| 指标 | 实测 |
|---|---|
| `POST /auth/login` 净耗时 | 200ms |
| token 落盘（secure storage 两枚） | 7ms |
| 点击「登录」→ 拿到 token | 212ms |
| 点击「登录」→ 登录页 pop 完成 | 236ms |
| 冷启动四域并发（/health 88ms、/finance 308ms、/lifestyle 309ms、/investment 716ms） | 整体被 investment 拖到 ~720ms |
| 改后（财务优先 + 每域 notifier + 内存缓存） | finance 160ms、health 60ms、lifestyle 129ms、investment 640ms |

### 结论（真因）
1. **secure storage 写盘不是主因**：并行写两枚 token 仅 7ms，且不在首帧路径上。
2. **主因一：四域同时发请求**。四路请求 + JSON 解析在同一帧窗口内互相挤占，investment 最慢把首屏拖长。
3. **主因二：IndexedStack 五根页全量重建**。原实现共用一个 `ChangeNotifier`，
   任一域返回都会 `notifyListeners()` 把五个根页（含 IntrinsicHeight 网格）全部重建。
4. 「点击登录 → 出现加载态」之间**没有空档**（212ms vs 200ms 网络耗时，差值即同步开销）。

### 改法
- `OverviewController` 拆成四个 `ValueNotifier<OverviewState<T>>`，页面用
  `ListenableBuilder` 只订阅自己那一域；设置页用 `Listenable.merge` 看聚合状态。
- `refreshAll()` 先拉财务（默认落地页），其余三域随后 `Future.wait` 并发。
- `TokenStore` 增加内存缓存，读 token 不再每次进平台通道；写两枚 token 用 `Future.wait`。
- 登录成功不重建整棵树：登录页直接 `pop` 回来源页，总览按域增量刷新。

---

## 3. A3 离线冷启动区分「未登录」与「连接失败」

### 实现
- `AuthService` 新增 `hasLocalSession` / `connectionFailed` / `restoreError`：
  - 无 token → `unauthenticated`（引导登录）；
  - 有 token 但 `/auth/me` 网络/超时/5xx → `connectionFailed`，**保留令牌与登录态**；
  - 401 才清令牌回未登录。
- `LoadStatus` 增加 `connectionFailed`；`OverviewStatusBanner` 该分支显示
  「连接失败，已保留登录状态」+ 原因 + 「重试」。
- 设置页状态行同步区分，账户卡在连接失败时给「重试」而不是「登录」。

### 真机验证（断网冷启动：`svc wifi/data disable` + force-stop + 重新启动）
| 截图 | 内容 |
|---|---|
| `screenshots/p3_a3_offline_finance.png` | 财务页顶部「连接失败，已保留登录状态」+ 原因 + 重试；未被踢到登录页 |
| `screenshots/p3_a3_offline_settings.png` | 设置页「连接失败 / 已保留登录状态，网络恢复后可重试」，状态行「连接失败（已保留登录状态）」 |
| 恢复网络后点重试 | 回到「已登录（admin）/ 总览数据 已加载 / 头像加载」 |

---

## 4. A4 手机端头像（契约对接）

### 接口
| 用途 | 方法/路径 | 说明 |
|---|---|---|
| 上传 | `POST /api/v1/user/avatar` | multipart，字段 `file`；`onSendProgress` 映射到进度条 |
| 外链/清空 | `PUT /api/v1/user/avatar` | `{"avatar_url": "https://..."}`，`null` 清空 |
| 回读 | `GET /api/v1/user/profile` | 写成功后回读，保证设置页与其它头像位一致 |

### 客户端校验（与后端同规则，不等 413）
- 扩展名仅 `png/jpg/jpeg/webp`；体积上限 `2,097,152` 字节（`AvatarRules`）。
- 外链仅 `http/https`、长度 ≤255；非法输入在对话框内给中文 SnackBar 并保留对话框。
- 404 时提示「当前后端不支持头像接口（404），请确认后端已更新」。

### 压缩策略
- 用 `image_picker 1.2.4` 的原生解码参数做缩放：`maxWidth: 1024, maxHeight: 1024, imageQuality: 85`。
- 好处：不引入图像库、不在 Dart 主 isolate 解码大图、天然剥离 EXIF 方向以外的元数据；
  正常手机照片落在 100–600 KB。缩放后仍 >2 MB 则中文提示重选。
- 不做裁剪（后端不处理裁剪）。

### 权限声明
- Android 13+ 走系统 Photo Picker（`image_picker` 的 `pickImage`），**不需要** `READ_MEDIA_IMAGES`；
  故未新增任何存储权限，只沿用 P1 的 `INTERNET`。

### 验收（真机）
| 截图 | 路径 | 结果 |
|---|---|---|
| `screenshots/p3_a4_avatar_sheet.png` | 头像面板 | 三项：从相册选择 / 填写图片地址 / 移除头像 + 压缩说明 |
| `screenshots/p3_a4_avatar_url_set.png` | 填外链 | 保存后回设置页、SnackBar「头像已更新」、账号 admin 与「已登录（admin）」保持 |
| `screenshots/p3_a4_avatar_removed.png` | 移除 | 回占位「成」字，SnackBar「头像已移除」 |
| `screenshots/p3_a4_avatar_uploaded.png` | 相册上传 | 选择系统相册图片 → 上传 → 回设置页 SnackBar「头像已更新」；`/user/profile` 返回 `/api/v1/uploads/avatars/7ec2c50655a4455d80c4813f6d7fb223.png`，App 拼接 Origin 后正常渲染 |

> 说明：9515 后端已是新版本（`/user/avatar` 返回 401/200 而非 404），未重启用户服务。
> 验证结束后已把 admin 头像还原为原始外链。

### 本轮顺带修掉的两个真 bug
1. **设置页整页 body 空白**：主题 `filledButtonTheme.minimumSize` 误用 `Size.fromHeight(48)`
   （= `Size(infinity, 48)`），`FilledButton` 放进 `Row` 后强制无限宽 → `BoxConstraints forces an infinite width`
   断言 → `_ScaffoldLayout` 在 body 处中断，整页 body 不绘制。改为 `Size(64, 48)`。
2. **保存外链后红屏**：`_editUrl()` 在 `showDialog` 返回后立刻 `dispose()` 控制器，
   而对话框退场动画期间 `TextField` 仍会重建 → `TextEditingController was used after being disposed`
   → 子树构建失败连带 `InheritedElement.debugDeactivated` 的 `_dependents.isEmpty` 断言。
   改为由 `_AvatarUrlDialog`（StatefulWidget）自持控制器、在自身 `dispose()` 释放。
3. **头像刷新后账号变空**：`GET /user/profile` 不返回 `account` / `is_admin`，
   `refreshProfile()` 整体替换用户对象导致「账号」为空。改为与现有用户合并后再覆盖资料字段。

---

## 5. 已知限制 / 待跟进

- 局域网内上传太快，进度条只闪现一帧，未能在截图中稳定捕获中间百分比（代码路径已接 `onSendProgress`）。
- 上传图片未做服务端 2 MB 边界用例（本地校验已覆盖，413 文案已接）。
- 手选相册用的是系统 Photo Picker；部分国产 ROM 首次会弹「安全访问」说明页，属系统行为。
