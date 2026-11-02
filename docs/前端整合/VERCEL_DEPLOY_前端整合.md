# Vercel 部署说明（前端演示版）

> 适用仓库：`ZeroOneCN/LifeOS2`　适用目录：`frontend/`　文档核对提交：`01a192c`
> 本文所有结论均来自仓库内代码与配置，未做推测。

## 0. 三条先记住

| 项目 | 取值 |
| --- | --- |
| 演示账号 / 密码 | `demo` / `demo123456` |
| 环境变量 | `VITE_DEMO` = `1`（必须精确为字符串 `1`） |
| Root Directory | `frontend`（仓库根目录已没有 `vercel-demo/`） |

补充：mock 登录**只校验账号是否为 `demo`，不校验密码**（`handleLogin` 里没有比对密码字段）。密码 `demo123456` 是公开演示值，出现在 mock 的错误提示、登录页预填提示和快照的站点文案里。

---

## 1. 先核实的事实

### 1.1 演示账号来源

- 账号校验写死在 [mock-api.ts](file:///c:/Code/LifeOS2/frontend/src/demo/mock-api.ts#L404-L412)：`handleLogin()` 只判断 `account === 'demo'`，不匹配则返回 `401` 并提示「演示环境请使用账号 demo / 密码 demo123456 登录」。
- 登录成功后返回固定令牌 `demo-access-token` / `demo-refresh-token`，用户对象从快照 `/api/v1/auth/me` 读取（`account: demo`、`nickname: 生活家`、`is_admin: true`）。
- 密码 `demo123456` 出现在三处：mock 的 401/403 提示文案、登录页 `IS_DEMO` 预填与提示块、`POST /site-config/reset` 的 fallback 常量。**不存在真实的账号表或密码校验**。
- 注册入口：登录页底部「去注册」链接仍然可见，演示模式**没有隐藏入口**；但提交注册时 mock 固定返回 `403`「演示环境已关闭注册，请使用演示账号 demo / demo123456 登录」。即「服务端（mock）拒绝」而非「界面隐藏」。
- 页面文案来自快照的 `/api/v1/site-config`：`login_subtitle` 为「使用演示账号体验全部功能」、`register_subtitle` 为「创建账号以体验个人生活管理」。只有管理员触发 `POST /site-config/reset` 后，注册副标题才会变成「演示环境未开放注册」（fallback 常量，见 [mock-api.ts](file:///c:/Code/LifeOS2/frontend/src/demo/mock-api.ts#L643-L660)）。

### 1.2 `VITE_DEMO` 开关

- 读取位置：[demo-mode.ts](file:///c:/Code/LifeOS2/frontend/src/lib/demo-mode.ts#L1-L7) 导出 `IS_DEMO = import.meta.env.VITE_DEMO === '1'`；[main.tsx](file:///c:/Code/LifeOS2/frontend/src/main.tsx#L16-L20) 用同一表达式决定是否 `await import('./demo/mock-api')` 后再挂载。
- **构建期注入**：`import.meta.env.VITE_*` 由 Vite 在打包时做字符串替换并参与常量折叠，因此运行期再改环境变量不会生效，必须重新构建。
- **无默认值**：未设置时 `import.meta.env.VITE_DEMO` 为 `undefined`，`IS_DEMO` 为 `false`，不加载 mock，所有请求走同源真实 `/api/v1`。
- 只认 `'1'`：填 `true`、`TRUE`、`yes` 都不生效。

### 1.3 构建配置

[vercel.json](file:///c:/Code/LifeOS2/frontend/vercel.json) 实际内容：`framework: vite`、`buildCommand: npm run build`、`outputDirectory: dist`、`rewrites` 把所有路径 `/(.*)` 指向 `/index.html`。

[package.json](file:///c:/Code/LifeOS2/frontend/package.json) 的 `build` 脚本是 `tsc -b && vite build`。`tsc -b` 失败时整条命令以非 0 退出，**Vercel 构建直接失败、不会产生新部署**（常见于类型错误，需先本地 `npm run build` 修好）。

### 1.4 Node 版本

`package.json` 未声明 `engines`。实际依赖要求（读自 `node_modules`）：

- `vite@8.2.2`：`node ^20.19.0 || >=22.12.0`
- `@vitejs/plugin-react@6.1.1`：`node ^20.19.0 || >=22.12.0`

Vercel 上选 **Node.js 22.x**（满足 `>=22.12.0`；20.x 必须 ≥20.19.0）。不要用 18.x。

### 1.5 演示模式与真实模式的差异

- **拦截范围**：只拦截同源、路径以 `/api/v1/` 开头的请求，方法不限（GET/POST/PUT/PATCH/DELETE）；其他请求（字体、JS、CSS、图标）原样走网络。安装位置见 [mock-api.ts](file:///c:/Code/LifeOS2/frontend/src/demo/mock-api.ts#L1131-L1174)。
- **数据来源**：内置 `snapshot.json`，按「路径 + 查询参数最匹配」取条目；未匹配到的接口返回 `404 {"detail":"接口不存在"}`。
- **特殊实现**：登录/刷新/登出/注册/`/auth/me`、用户资料与设置、站点配置、会话吊销、备份下载、报告 PDF 导出、`/health/checkup/stats`、`/health/diet/estimate`、`/health/fitness/estimate`、旅行报告详情等由代码现算或现造，不走快照原值。
- **写操作落点**：新增/编辑/删除写入 localStorage 的 **`lifeos:demo-store:v1`**（`overrides.lists` 存分页集合、`overrides.objects` 存对象/数组），刷新后保留；清掉该 key 即恢复初始演示数据。
- **登录态**：令牌存在 `lifeos_token`（`lifeos_refresh_token` 存刷新令牌），与真实模式同一个 key。
- **统计数字**：快照里共有 32 个 `/stats` 接口，绝大多数**原样返回快照值**，写操作后统计数字不会变化（刷新也不变）；例外是 `/health/checkup/stats`（按明细实时聚合）以及饮食/运动热量估算（按已记录条目换算）。这是演示层的已知差异，不是 bug。
- **分页/筛选**：列表的本地修改按快照条目的完整 key（含查询串）保存，因此刷新时页面必须发出同样的默认查询才能看到修改。

---

## 2. A. 全新部署（从零开始）

1. 打开 <https://vercel.com>，进入团队 Dashboard。
2. 右上角 **Add New… → Project**。
3. 在 **Import Git Repository** 列表找到 `ZeroOneCN/LifeOS2`，点 **Import**（首次需授权 GitHub）。
4. 进入 **Configure Project** 页，按下表填写：

| 字段 | 准确取值 | 为什么 |
| --- | --- | --- |
| Project Name | 自定义，如 `lifeos-demo` | 决定默认域名 `<name>.vercel.app` |
| Framework Preset | **Vite** | 仓库是 Vite 8 + React 19；`vercel.json` 也声明了 `framework: vite` |
| Root Directory | **`frontend`**（点 *Edit* 后填写） | 仓库根目录没有 `package.json`，`package.json`、`vercel.json`、`src/` 都在 `frontend/`；旧副本 `vercel-demo/` 已删除 |
| Build Command | `npm run build`（保持默认/自动读取） | 实际执行 `tsc -b && vite build`，先类型检查再打包 |
| Output Directory | `dist` | 与 `vercel.json` 一致 |
| Install Command | 留空（默认 `npm install`） | 仓库有 `frontend/package-lock.json`，默认安装即可；构建需要 devDependencies（含 `selfsigned`） |
| Node.js Version | **22.x** | Vite 8 要求 `^20.19.0 \|\| >=22.12.0`（在 Settings → General 里改，见下） |

5. 展开 **Environment Variables**，添加一条：

| Key | Value | Environments |
| --- | --- | --- |
| `VITE_DEMO` | `1` | Production、Preview（Development 可一并勾选，只影响 `vercel dev`） |

> 值必须是 `1`，不要填 `true`。变量名区分大小写。

6. 点 **Deploy**，等待状态变为 **Ready**。
7. 打开生成的域名（形如 `https://lifeos-demo.vercel.app`）验证，见 C 节。

> Node 版本若不在此页设置，部署后到 **Settings → General → Node.js Version** 选 `22.x`，保存后按 B 节方式重新部署一次。

---

## 3. B. 已有项目改造（原 Root Directory 指向 `vercel-demo`）

1. 进入项目 → **Settings → Build and Development Settings**。
2. 找到 **Root Directory**，点 **Edit**，把 `vercel-demo` 改成 **`frontend`**，保存。
3. 进入 **Settings → Environment Variables**，确认存在 `VITE_DEMO = 1`，且 Production（以及 Preview）已勾选；没有就新增。
4. **必须重新部署**：Root Directory 与变量变更都不会自动作用到已有部署。到 **Deployments** 标签，选最新一条，右侧 **⋯ → Redeploy**。
5. 在 Redeploy 弹窗中**取消勾选 “Use existing Build Cache”**，再点 Redeploy。旧缓存对应的是 `vercel-demo` 的构建产物，复用会得到错误结果；若项目设置里有独立的 Build Cache 开关（Settings → General），一并临时关闭，部署成功后再按需开启。
6. 部署完成后打开域名验证（C 节）。旧项目的历史部署记录可以保留，不影响新版本。

> 只改 Root Directory 不重新部署：站点仍指向旧构建，通常是 404 或旧内容；只加变量不重新部署：仍跑在「真实 API 模式」，见 D 节。

---

## 4. C. 部署完成后如何验证

### C1. 域名能打开
访问 `https://<project>.vercel.app`，应看到登录页，标题「**登录 LifeOS 演示空间**」，副标题「使用演示账号体验全部功能」，并有一块「演示账号：demo　密码：demo123456」的灰底提示（该提示只在演示构建里出现）。账号、密码输入框已预填 `demo` / `demo123456`。

### C2. 能登录
直接点「登录」，应进入 `/home`；浏览器 localStorage 出现 `lifeos_token`，值为 `demo-access-token`。若账号不是 `demo`，会收到 401 提示。

### C3. 数据确实来自 mock（可判断特征）
打开开发者工具 Network：

- **看不到任何 `/api/v1/*` 请求**（被页面内的 fetch 拦截器吃掉），但页面有数据、单个请求约有 120ms 延迟——这是最直接的证据。
- 右上角站点名/标题为「LifeOS 演示空间」；`/auth/me` 返回 `account: demo`、`nickname: 生活家`、`is_admin: true`。
- 演示用户是管理员，所以 `/sessions`、`/system-settings`、`/backup` 等管理员页可正常进入（真实环境普通账号会被弹回 `/home`）。
- 进入「财务 → 债务/账单」等页面，数据为快照内容（例如账单页显示若干笔逾期记录）。

### C4. 刷新子页面不 404（SPA 重写生效）
在地址栏直接打开一个深层路由，例如 `https://<project>.vercel.app/finance/debts`，或在任意页面按 F5。应正常回到该页面，而不是 Vercel 的 404 页。重写规则来自 `frontend/vercel.json` 的 `rewrites`。

### C5. 写操作刷新后仍在
任选一个有增删改的页面（如「财务 → 债务」）新增一条记录 → 刷新页面 → 记录仍在。同时 localStorage 出现 `lifeos:demo-store:v1`。清掉该 key 后刷新，数据恢复初始快照。

> 预期内：新增记录后，页面顶部/统计卡片里的汇总数字**不会**跟着变（统计接口返回快照固定值）。想验证「写操作生效」请看列表本身，不要看统计卡片。

---

## 5. D. 忘记配置环境变量怎么办

### 原理
`VITE_*` 是**构建期**注入：Vite 在打包时把 `import.meta.env.VITE_DEMO` 替换成字面量，未设置时替换为 `undefined`，并据此把 mock 分支裁掉（生产包中根本不会生成 mock chunk）。因此：

- 在 Vercel 控制台**运行期**改环境变量，对已经部署的站点**没有任何影响**；
- 只加变量、不重新构建 = 没加。

### 补救步骤（按顺序）
1. 项目 → **Settings → Environment Variables**。
2. 新增：Key `VITE_DEMO`，Value `1`，Environment 勾选 **Production** 与 **Preview**（用 `vercel dev` 的话再勾 Development）。保存。
3. 到 **Deployments**，选最新一条 → **⋯ → Redeploy**。
4. 弹窗里**取消勾选 “Use existing Build Cache”**，确认 Redeploy。必须重新构建，不能复用缓存产物。
5. 若使用 CLI：在仓库根执行 `vercel --prod`（同样会重新构建）。

### 怎么判断真的生效
满足任意两条即可确认：

1. **构建日志**的产物清单里出现 `mock-api-*.js`（约 317 kB），以及主包约 470 kB；未生效时不会有 `mock-api` 这个 chunk。
2. 打开站点，**Network 中没有 `/api/v1/*` 请求**（全被页面内拦截），但页面数据正常。
3. 登录页出现「演示账号：demo　密码：demo123456」提示块，且输入框已预填。
4. 登录成功后 localStorage 有 `lifeos_token`，值恰为 `demo-access-token`。

### 只加变量但不重新构建会看到什么
- 站点仍是**真实 API 模式**：`POST /api/v1/auth/login` 被 `rewrites` 回落成 `index.html`（HTTP 200 + `text/html`，**不是 404**），前端 `res.json()` 解析失败，控制台报 `Unexpected token '<'`，页面提示登录失败。
- 其它页面请求同样拿到 HTML，表现为「数据一直为空」「加载不出来」；个别未捕获异常可能导致局部白屏。
- 因此排查时看到「接口返回 200 但内容是 HTML」基本就是「变量没生效 / 没重新构建」。

---

## 6. E. 常见故障对照表

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 打开是白屏 / 只有空白 | 主包或资源 404（Root Directory 指错、产物目录不对）；或部署未 Ready | 看 Deployment 是否 Ready；看 Build 日志是否成功、产物是否为 `dist`；确认 Root Directory = `frontend`；清缓存重新部署；看控制台是否有资源 404 |
| 登录提示 401 | 账号不是 `demo`（mock 只认这个账号）；或站点其实在真实模式、后端返回 401 | 用 `demo` / `demo123456`；确认 `VITE_DEMO=1` 且已重新构建 |
| 登录失败，控制台 `Unexpected token '<'` | `/api/v1/*` 被 SPA 重写回落成 HTML，说明是真实模式（变量未生效） | 按 D 节加变量并 Redeploy（不复用缓存） |
| 刷新子页面 404 | `rewrites` 未生效：`vercel.json` 不在 Root Directory 内，或 Root Directory 不是 `frontend` | 确认 `frontend/vercel.json` 存在且 Root Directory = `frontend`；重新部署 |
| 页面能开但数据为空 | mock 未命中该路径（返回 `404 接口不存在`）；或之前写入的本地覆盖破坏了该集合 | 清 localStorage 的 `lifeos:demo-store:v1` 后刷新；看 Network/控制台是否有「接口不存在」 |
| 部署成功，但打开后请求真实 `/api/v1` 报错 | 忘了设 `VITE_DEMO`，或部署指向了错误目录（部署的不是 `frontend`） | 加变量 + 改 Root Directory + 重新构建（D 节） |
| 新增记录成功但统计数字不变 | 预期行为：多数 `/stats` 返回快照固定值 | 无需处理；用列表数据判断写操作是否生效 |
| 构建报 Node 版本相关错误 | Node <20.19 / <22.12 | Settings → General → Node.js Version 选 `22.x`，重新部署 |
| 构建失败且日志是 TypeScript 报错 | `npm run build` 含 `tsc -b`，类型错误会中断 | 本地 `cd frontend && npm run build` 复现并修复后推送 |
| 改了 Root Directory 但站点还是旧的 | 目录变更只在下次构建生效 | 手动 Redeploy（不复用缓存） |
| 演示数据想恢复初始状态 | 本地写操作存在 localStorage | 清站点 localStorage 的 `lifeos:demo-store:v1`（或浏览器「清除站点数据」） |

---

## 7. 参数速查

```text
Repository        ZeroOneCN/LifeOS2
Root Directory    frontend
Framework Preset  Vite
Install Command   (默认 npm install)
Build Command     npm run build        # = tsc -b && vite build
Output Directory  dist
Node.js Version   22.x
Environment       VITE_DEMO=1          # Production / Preview
SPA 重写          frontend/vercel.json → /(.*) → /index.html
演示账号          demo / demo123456
本地写操作        localStorage: lifeos:demo-store:v1（登录态: lifeos_token）
```
