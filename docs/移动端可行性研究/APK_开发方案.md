# LifeOS Android APK 开发方案（技术方案）

> 范围：Android APK，独立设计前端、不复用现有 Web UI；后端作为接口契约原样复用。
> 本文只做研究与方案，不含代码、不建工程、不改现有前端。
> **导航与页面布局已重新推导，统一见 [APK_界面布局方案.md](./APK_界面布局方案.md)**，本文不再保留旧导航结论。

---

## 0. 结论前置

| 议题 | 结论 |
|---|---|
| 导航形态 | **底部 5 Tab（健康 / 财务 / 生活 / 投资 / 设置），Tab 为唯一一级导航；无抽屉、无首页**（详见布局方案） |
| 页面总量 | **30 个**（路由页 28 + 登录/首启动 2）；手机端实装 28 |
| 技术栈主推荐 | **Flutter**（独立 UI、M3 组件齐备、自签证书最省事、单代码库、Windows 可出 APK） |
| 技术栈备选 | **React Native + Expo**（沿用 TS 心智、EAS 云构建；自签证书与热更需额外配置） |
| 不推荐 | Capacitor 复用现有 Web UI（与"独立设计"目标冲突）；原生 Kotlin（单人成本过高） |
| 打包 | release APK + 按 ABI 拆分，仅 arm64-v8a；不上 Google Play 则不需要 AAB |
| 连接 | 首启动引导页配置服务器地址（输入 + 扫码）+ 连接测试；自签证书走 `network_security_config` 固定 |
| 签名 | keystore 独立保管、不入库；`versionCode` 单调递增，`versionName` 语义化 |
| 提醒 | App 本地通知 + 后端邮件/IM 渠道双轨；Android 13+ 首次开启提醒时申请权限 |
| 分发 | 内网 APK 下载页侧载；不上架 |
| 工作量（单人 + AI） | **23–31 人日**（Flutter 口径；5 Tab、域首屏、FAB 增量已计入，见 6.1） |

---

## 一、导航与界面布局（摘要）

一级导航已定为 **底部 5 Tab：健康 / 财务 / 生活 / 投资 / 设置**，Tab 是唯一一级导航：

- 不做抽屉、汉堡菜单、首页中枢；原"今日"首页取消，今日待办下沉到各 Tab 首屏头部，跨域待办由顶栏铃铛的通知中心承接；
- 全局浮层只有两个：每个 Tab 根页顶栏的铃铛、右下角「＋」FAB（四选一：支出 / 账单 / 用药 / 体重）；
- 页面 30 个（路由 28 + 登录/启动 2），手机端实装 28；逐条归属、Tab 栏规格、375dp 与 1.3x 字号推算、返回栈规则全部见下文链接。

**详见 [APK_界面布局方案.md](./APK_界面布局方案.md)。本文不重复任何导航参数。**

---

## 二、APK 技术路径对比

### 2.1 总览矩阵

| 维度 | Capacitor（全新 UI） | React Native + Expo | Flutter | 原生 Kotlin + Compose |
|---|---|---|---|---|
| 复用现有前端（90 文件 / 2.5 万行） | UI 0%（沿用现有 UI 才 100%）；仅 `api.ts` 约 230 行可参考 | UI 0%；API 层/类型约 3–5% | 0% | 0% |
| 页面工作量 | 28 路由页 + 2 入口页，Web 端另加 30 个新组件 | 28 路由页 + 2 入口页，32 个组件 | 28 路由页 + 2 入口页，30 个 Widget | 28 路由页 + 2 入口页，32 个 Composable |
| 图表（现有 Recharts，约 5 页） | 直接沿用 Recharts | 换 `victory-native`/`gifted-charts`，3 类图 × 5 页重写 | 换 `fl_chart`，同上 | 自绘或 MPAndroidChart |
| 表格密集页（16 页 / 1,132 处引用） | 复用 Web 表格能力最强 | `FlatList` + 卡片，工作量中 | ListView + 卡片，工作量中 | 同 Flutter |
| 表单与弹窗 | Web 组件，改造成本低 | 需自建 BottomSheet/键盘避让 | `showModalBottomSheet` 原生支持好 | M3 组件最标准 |
| 本地通知 / 定时 | `@capacitor/local-notifications`，精确闹钟需授权 | `expo-notifications`，精确排程「待验证」 | `flutter_local_notifications` + timezone，成熟 | AlarmManager，最可控 |
| 文件导出（SQL/JSON 备份、Excel） | Blob → Filesystem/Share | FileSystem + Sharing | path_provider + share_plus | MediaStore/SAF |
| PDF 预览 | 系统查看器 / PDF.js | `expo-intent-launcher` 或内置组件 | `open_filex` / `pdfx` | PdfRenderer / WebView |
| 局域网 HTTP | WebView `usesCleartextTraffic` | `expo-build-properties` 配置 | `android:usesCleartextTraffic` | 同左 |
| **自签 HTTPS** | WebView 需忽略证书错误（最弱） | network_security_config + 打包证书「待验证」 | `badCertificateCallback` 指纹校验，**最省事** | network_security_config，标准 |
| 包体积（arm64，估算） | 8–12 MB | 20–30 MB | 12–18 MB（拆分）/ 25 MB（通用） | 6–10 MB |
| 热更新 | **Web 资源可远程更新**（侧载可行） | EAS Update / 自建更新服务「待验证」 | 无官方方案；Shorebird「待验证」 | 无 |
| Windows 上出 Android 包 | ✅ | ✅ | ✅ | ✅ |
| 单人维护成本 | 低 | 中 | 中 | 高（且仅 Android） |
| 首版最大风险 | WebView 手感 + 证书绕过 | 自签证书配置、EAS 依赖账号/额度 | 学习 Dart、包体偏大 | 工作量翻倍、iOS 另写 |

### 2.2 主推荐与备选（改动量）

**主推荐：Flutter**
- 新增页面：路由页 28 + 登录/首启动 2，共 30 个（手机端实装 28）。
- 新增组件约 30 个（5 项 NavigationBar、FAB 与四选一弹层、4 套域首屏概览块、设置状态卡、待办行、指标卡、列表卡、金额输入、日期/月份选择、图表封装、空态/错误态、Toast、PDF 查看等）。
- 代码复用：0 行 UI；接口层按 `api.ts` 重写约 150–200 行（双令牌刷新、401 重试、并发刷新去重）。
- 明确不做：复用 Tailwind/shadcn/Radix、复用现有路由与页面。

**备选：React Native + Expo**
- 页面 28 个路由页 + 2 个入口页、组件约 32 个；图表 5 个页面重写；API 层改写约 150 行。
- 额外成本：自签证书需 prebuild + 网络安全配置；EAS 构建依赖账号与额度（外部条件）。

**不推荐**
- Capacitor 复用现有 Web UI：与"独立设计"冲突，且无法解决自签证书与手势问题；若选 Capacitor 应按全新 Web UI 计 28 个路由页 + 2 个入口页。
- 原生 Kotlin：页面数不变但单端交付，成本约 +30%，失去 iOS 可能。

---

## 三、打包与工程

### 3.1 工具链与 SDK

| 项 | 建议 | 说明 |
|---|---|---|
| JDK | 17（LTS） | AGP 8.x 要求 |
| Gradle / AGP | Gradle 8.7+ / AGP 8.5+ | 由框架模板生成，不手改版本 |
| compileSdk | 35（或 36） | 以 2026 年商店要求为准「待验证」 |
| `minSdk` | 26（Android 8.0） | 覆盖绝大多数在用设备；框架默认下限更高时从其默认 |
| `targetSdk` | 35（或 36） | 对齐 compileSdk；适配 13+ 通知权限、14+ 前台服务类型 |
| ABI | 仅 `arm64-v8a`（必要时加 `armeabi-v7a`） | 按 ABI 拆分减包；x86 仅模拟器 |
| 架构分包 | `splits { abi }` + `universalApk false` | 侧载分别发 arm64 包 |

### 3.2 签名

- 生成：`keytool -genkeypair` 生成 `lifeos-release.jks`，RSA 2048，有效期 25 年以上。
- 保管：keystore 与口令不入仓库（`.gitignore`），放密码管理器 + 加密离线备份；丢失无法覆盖升级。
- 配置：`signingConfigs.release` 从环境变量或 `keystore.properties`（不入库）读取。
- 版本：`versionCode` 单调递增（建议 `年周` 或 `主×10000+次`），`versionName` 语义化；debug 与 release 分离。
- 校验：发布前 `apksigner verify --print-certs` 确认指纹一致。

### 3.3 APK 还是 AAB

| 产物 | 用途 | 取舍 |
|---|---|---|
| APK（按 ABI 拆分） | 侧载、内网分发 | **主产物** |
| AAB | Google Play 上传 | 不上架则不需要；测试可用 bundletool 转换 |
| 通用 APK | 兼容异常机型 | 兜底 |

结论：**只出 arm64 release APK**，另备 universal APK。

### 3.4 构建位置

| 方式 | 前提 | 坑 |
|---|---|---|
| Windows 本地 Gradle | Flutter SDK / Android Studio + JDK 17 + SDK 35 | 首次依赖下载慢；路径含空格/中文易出错；杀软拦截 |
| WSL2 | 同上 + Linux SDK | USB 调试需 usbipd；路径映射问题多，不作主构建 |
| GitHub Actions | 仓库 + Secrets（keystore base64） | 私有仓库免费额度有限；密钥入 Secret；缓存 Gradle |
| EAS 云构建（RN 专属） | Expo 账号，免费额度「待验证」 | 排队/额度；自签证书与原生配置需 config plugin |

建议：日常 Windows 本地构建；需要可复现交付时加一条 GitHub Actions 流水线。

---

## 四、运行时与连接

### 4.1 服务器地址配置

推荐 **首启动引导页（输入 + 扫码）+ 设置内可改 + 连接测试**：

- 首启动必做，含"测试连接"按钮（请求公开健康检查端点，具体端点以现有后端为准「待验证」）；
- 扫码为加速项：桌面端生成二维码（内容为 base URL）；
- 设置可改，切换后清空本地缓存与登录态，避免串服；
- 不做写死地址（局域网 IP 会变）。

### 4.2 明文 HTTP 与自签 HTTPS

- **HTTP**：`android:usesCleartextTraffic="true"`（或 network_security_config 仅放行内网）。仅调试/内网使用。
- **自签 HTTPS**：
  - 推荐：把服务端证书（或 CA）打进 `res/raw`，`network_security_config.xml` 的 `trust-anchors` 固定到该证书，仅对目标域名生效；
  - Flutter：`HttpClient.badCertificateCallback` 做证书 SHA-256 指纹比对；禁止 `trustAllCerts`；
  - WebView（Capacitor）需 `onReceivedSslError` 特判，「待验证」且安全性最差；
  - CORS 对原生 App 不适用，无需改后端。
- **现状核对**：仓库内未发现 uvicorn/Nginx 的 HTTPS 配置（`.env`、`main.py` 均无 ssl 参数），README 也是 HTTP 部署；"HTTPS 自签"很可能由本机 Nginx/反代终止 TLS。「待验证：签发方、域名/IP、端口」

### 4.3 登录态存储与刷新

- 存储：Android Keystore 支持的加密偏好（RN `expo-secure-store`；Flutter `flutter_secure_storage`；Kotlin `EncryptedSharedPreferences`）。
- 令牌：access 24h、refresh **365 天**且刷新轮换（见 `auth.py`），客户端必须同步落盘新 refresh。
- 刷新：401 → 单飞刷新（并发去重）→ 重放一次；失败则清空并回登录；恢复前台时校验 `/auth/me`。
- 会话：后端 `UserSession` 记录设备/IP；移动端登录带设备标识（如 `LifeOS-Android`）。
- 登出：先调用 `/auth/logout` 传 refresh，再清本地；离线允许本地登出。

### 4.4 提醒：本地通知 + 邮件双轨

现状：后端 APScheduler 每日扫描（`NOTIFY_SCAN_TIME`，`.env.example` 默认 `00:00`，README 写 08:30，**以实际 `.env` 为准**「待验证」），渠道含邮件/钉钉/飞书/企微/TG/Webhook；`POST /api/v1/notifications/scan` 可手动触发。

| 通道 | 角色 | 说明 |
|---|---|---|
| App 本地通知 | 即时提醒（用药、账单、体检） | 启动/回前台拉取近期待办并本地排程，不依赖服务器推送 |
| 后端邮件/IM | 兜底 | App 未打开、被杀、无通知权限时仍可达 |
| 推送 | 不建设 | 局域网无 FCM/厂商通道 |

- Android 13+：首次开启"提醒"时申请 `POST_NOTIFICATIONS`，先解释再弹系统框；拒绝后给"去设置"入口。
- 精确闹钟：Android 12+ `SCHEDULE_EXACT_ALARM` 需授权，或改非精确（±15 分钟）；Android 14 默认收紧「待验证」。
- 重启恢复：监听 `BOOT_COMPLETED` 重新排程（插件支持「待验证」）。
- 现实预期：国产 ROM 省电策略可能延迟/不触发；提供"忽略电池优化"引导，并告知关键提醒同时启用邮件。

### 4.5 真机适配必测清单

| 项 | 风险点 | 验收 |
|---|---|---|
| 安全区/刘海/挖孔 | 顶栏遮挡 | 状态栏不重叠；inset 正确 |
| 手势条 | 底栏/FAB 与手势条重叠、误触 | 预留 16–24dp inset |
| 深色模式 | 选中态对比度、图表配色 | 跟随系统；切换不重启 |
| 字体缩放 1.3x | 行高撑破、金额截断、短标签仍溢出 | 最小高度；金额自适应；5 个根页 + 表单页专项 |
| 小屏 320dp | 5 格热区偏密、根页首屏拥挤 | 2 字短标签（31.2dp ≤ 48dp 可用宽）；根页首屏最多 2 区块 |
| 横屏 | Tab 栏占高、键盘遮挡、双栏过窄 | <480dp 高度时内容区纵向滚动；表单单列；≥840dp 换 NavigationRail |
| 长文本 | 标题/备注溢出 | 单行省略 + 点按展开 |
| 数字键盘 | 金额精度、千分位、小数点 | 独立金额输入；关闭自动纠错 |
| 弱网/不可达 | 白屏、无限 Loading | 统一错误态 + 重试 + 改地址入口 |
| 时区 | 本地通知时间偏移 | 按设备时区计算 |

---

## 五、分发与合规

| 方向 | 结论 |
|---|---|
| 侧载 | `adb install` 或文件管理器安装，需授权未知来源；适合自用 |
| 内网分发 | 内网文件服务/现有后端放 APK + 版本清单（versionCode、SHA-256、更新说明）；App 内检查更新。无需商店 |
| Google Play | 需开发者账号（一次性注册费，金额以官网为准「待验证」）、隐私政策、Data safety、targetSdk 年度要求；健康/金融类审核更严。**不上架** |
| 国内应用商店 | 需软著、App 备案、隐私政策、权限清单、实名；个人主体对金融/健康类目限制严格。**不上架** |
| 隐私 | 数据全在自有服务器；不引入第三方统计/广告 SDK |

---

## 六、阶段计划与风险

### 6.1 阶段划分（单人 + AI 协作口径，粗估）

| 阶段 | 目标 | 主要产出 | 前置条件 | 人日 |
|---|---|---|---|---|
| P0 原型验证 | 能连、能登、能画、能提醒 | 验证 APK：自签 HTTPS 连通、登录+刷新、1 个图表、1 条本地通知、5 Tab 切换与返回 | 服务器地址与证书确认；Android SDK 就绪 | 1–2 |
| P1 骨架 | 导航与基础设施定稿 | 设计 token、底部 5 Tab（短标签）+ 每 Tab 独立栈 + 铃铛 + FAB、路由与返回语义、请求层、错误/Toast、深色模式、安全区 | P0 通过；UI 走查基线确认 | 3–4 |
| P2 核心页 | 覆盖 T0/T1 | 健康总览、财务总览、用药跟踪、账单管理、设置（5 个根页/核心页）+ FAB 四选一弹层 + 金额/日期/底部表单等 12 个基础组件 | P1 完成 | 6–8 |
| P3 剩余页 | 补齐其余 23 页 | 生活/投资总览 + 域内一级页 + 设置子页（登录设备/备份/安全与日志）+ 列表/筛选/分页/图表封装/文件下载与 PDF 预览 | P2 组件稳定 | 8–11 |
| P4 打磨发布 | 可长期使用 | 通知与权限引导、离线/弱网态、字体缩放与横屏、签名与内网分发页、回归清单 | P3 完成；keystore 就绪 | 3–4 |
| 合计 | | | | **23–31** |

**相对上一版（21–29）的重算**

| 变动 | 人日 |
|---|---|
| 去掉抽屉、汉堡、抽屉分组目录与常用组补偿 | −1 ~ −1.5 |
| 去掉"今日"首页（1 页） | −0.5 ~ −1 |
| 4 个域总览页改造为"待办头 + 指标 + 入口 + 列表" | +1 ~ +1.5 |
| 设置根页重塑（账户卡 + 状态区 + 目录） | +0.5 ~ +1 |
| 5 项 Tab 容器、每 Tab 独立栈与状态保留、短标签适配 | +1 ~ +1.5 |
| 全局 FAB 扩展为跨域四选一（原 FAB 已有） | +0.5 |
| 页面数口径修正（27 → 30：取消首页 −1、补计 4 个管理员页 +4；实装 28） | 0 ~ +0.5 |
| **净变化** | **约 +1.5 ~ +2.5，总量 23–31** |

说明：不含视觉稿外包与后端改造；RN 约同量级，Kotlin 约 +30%。

### 6.2 风险清单（按影响排序）

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| 1 | 自签 HTTPS 证书校验失败 | App 完全不可用 | P0 先验证；Flutter 指纹校验；兜底内网 HTTP |
| 2 | 国产 ROM 后台清理导致本地通知不触发 | 提醒漏发 | 双轨邮件/IM；引导关闭电池优化；各域根页待办头部常驻 |
| 3 | Android 12+/14 精确闹钟权限收紧 | 提醒时间漂移 | 允许 ±15 分钟非精确；引导授权 |
| 4 | 30 页重写超预期 | 延期 | 先组件库后页面；P3 按模块分批，先生活+投资 |
| 5 | 5 个 Tab 热区过密导致误触 | 误操作 | 短标签 + 设置放最右；真机走查手势/三键导航 |
| 6 | 根页"待办 + 指标 + 入口 + 列表"塞太多 | 首屏拥挤 | 首屏最多 2 区块；财务/投资强制露出 2 行列表；按布局方案验收 |
| 7 | 表格页照搬小屏不可用 | 核心页不可用 | 统一"列表卡 → 详情 → 弹层表单"；禁止横向宽表 |
| 8 | 字体缩放 1.3x 布局崩 | 无障碍不合格 | Tab 用 2 字短标签；固定高度改最小高度；专项测试 |
| 9 | 无热更新（原生路径） | 改动需重装 | 内网分发页 + 版本检查 |
| 10 | 包体积超预期 | 分发不便 | 仅 arm64 + 资源压缩 + 分包 |
| 11 | 接口契约开发期变动 | 客户端返工 | 以 `openapi.json` 生成类型；变更先冻结 |
| 12 | 管理员功能误入手机端 | 安全/误操作 | 设置内折叠且默认隐藏；恢复导入仅桌面 |
| 13 | 5 格已满，后续新业务域无处可放 | 结构僵化 | 新域先并入现有 4 域；确需独立则重评导航（不做第 6 个 Tab） |
| 14 | 单人维护两套客户端（未来 iOS） | 成本翻倍 | Flutter 单代码库，iOS 只做构建适配 |

### 6.3 本轮明确不做

- 不初始化 Flutter/RN 工程，不写页面代码；
- 不改 `frontend/` 与 `backend/`；
- 不选定最终视觉稿（仅确定结构、尺寸、间距、动效与布局规则）。

---

## 附录 A：待验证清单

1. ~~M3 NavigationBar 的精确动效与选中指示尺寸（以组件库默认值为准）；1.3x 字号下短标签是否仍落在 80dp 内。~~ **部分验证（P1）**：默认值运行正常、1.3x 短标签不溢出；动效与指示器尺寸未做像素级测量。
2. 当前后端 HTTPS 的实际形态：uvicorn 还是 Nginx 终止 TLS、证书类型、地址端口。
3. `NOTIFY_SCAN_TIME` 实际值（`.env` 默认 `00:00`，README 写 08:30）。
4. `flutter_local_notifications` 在目标 ROM 的精确闹钟、重启恢复、免杀表现。
5. RN `expo-notifications` 精确排程能力与 EAS 免费构建额度。
6. Android 14 对 `SCHEDULE_EXACT_ALARM` 的默认授予策略与各 ROM 差异。
7. 2026 年 Google Play 要求的 targetSdk 与注册费。
8. Flutter/RN 仅 arm64 的实际包体积（估算 12–18 MB / 20–30 MB）。**P1 已取得 debug 基线 163.9 MB（通用包、未拆分 ABI），release + `splits { abi }` 仍未测。**
9. 各框架对 Android 14 预测性返回的支持程度。
10. ~~扫码配置所需的公开健康检查端点是否已存在。~~ **已验证（P1）**：`GET /api/v1/health` 匿名可访问，可作为连接测试端点。

## 附录 B：接口契约沿用提示

- 认证：`/api/v1/auth/{login,register,refresh,logout,me}`，双令牌 + 刷新轮换 + 登录锁定。
- 数据：108 个端点，统一分页 `items/total/page/page_size`。
- 文件：报告导出 PDF（`Content-Disposition`），备份导出 JSON/SQL/ZIP。
- 提醒：`POST /api/v1/notifications/scan` 手动触发；渠道含邮件/钉钉/飞书/企微/TG/Webhook。
