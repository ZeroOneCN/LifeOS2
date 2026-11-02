# 前端整合（第三批）验收报告

日期：2026-11-02　范围：`frontend/`、`vercel-demo/`（已删除）、`README.md`、`说明文档.md`

## 一、总体结论

三块全部完成并已分别提交、推送 master，无回退。

| 块 | 内容 | 提交 | 状态 |
| --- | --- | --- | --- |
| 1 | 路由单一真源（`config/routes.ts`） | `b95022a` | 完成 |
| 2 | 去掉双副本（mock 迁入 `frontend/src/demo/`，删除 `vercel-demo/`） | `9fe18b8` + `866f06e` | 完成 |
| 3 | 图表语义色（CSS 变量 + `lib/chart-theme.ts`） | 本次提交 | 完成 |

## 二、块 1 · 路由单一真源

- `routes.ts` 成为路由、侧边导航、面包屑标题的唯一真源；`adminOnly` 自动派生 `RequireAdmin`，手工 `ADMIN_PATHS` 已删除。
- `implementedPages` 死键处置：
  - `/health/diet`、`/health/body`、`/health/fitness/dashboard`：确认由 `FitnessTabsPage` 内部 tab 承载，不单独注册路由；
  - `/user-center`、`/user-center/settings`：确认由导航用户下拉菜单直达，保留为 `inNav: false` 的正常路由。
- 验收：`npm run build` 通过（主包 470.93 kB）；`npm run lint` 52 warnings / 0 errors；非管理员访问 `/sessions`、`/system-settings`、`/backup` 均跳 `/home`；`/user-center` 可直达。

## 三、块 2 · 去掉双副本

- mock 层迁入 `frontend/src/demo/`，`main.tsx` 仅在 `VITE_DEMO=1` 时动态 `import()` 后再挂载。
- 普通构建 78 个资源、主包 470.95 kB，产物无 mock chunk；`VITE_DEMO=1` 构建 79 个资源、主包 471.25 kB（+0.30 kB）、mock 独立 chunk 317.29 kB（gzip 52.95 kB）。
- 无后端静态托管实测通过：演示账号预填、登录进入 `/home`、`/finance/bills` 显示 mock 账单。
- `vercel-demo/` 已整目录删除（111 个文件）。

### 部署必须同步调整（重要）

现有 Vercel 项目的 **Root Directory 如果指向 `vercel-demo`，必须改为 `frontend`**，并在环境变量中补 `VITE_DEMO=1`；否则构建会因目录不存在而失败，或部署成需要真实后端 `/api/v1` 的版本。`frontend/vercel.json` 已提供 Vite 框架与 SPA 全量重写。

## 四、块 3 · 图表语义色

- `index.css`：`--chart-1..5` 由纯灰改为带色相，并扩展 `--chart-6..10` 以保留原 10 色饼图色板；新增 `--chart-muted`、`--chart-axis` 与 `--success/--warning/--danger/--info`，深浅两套。
- `lib/chart-theme.ts`：`useChartColors()` 从 CSS 变量读取具体颜色（SVG 表现属性不接受 `var()`），并用 `useSyncExternalStore` 监听 `<html>` class 变化，主题切换后图表自动换色；`resolveChartColor()` 负责令牌解析。
- 替换范围：`components/health/charts.tsx` 默认色/饼图色板/选中高亮，`pages/investment/forex.tsx`、`pages/investment/overview.tsx` 的渐变、基线、Area/Line/Bar/Cell，以及 11 个健康/财务/日志页面的 `series.color`。
- 硬编码 hex：`frontend/src` 内 **69 处 / 15 文件 → 0 处**；固定调色板类（337 处）按约定未动。
- 验收：`npm run build` 通过（主包 470.96 kB、gzip 146.90 kB）；`npm run lint` 52 warnings / 0 errors；演示构建实测 `/health/vitals-sleep` 深色模式下多条折线为不同颜色，控制台无报错。

### 新色板取值与对比度

浅色（600 级，白底）：`chart-1` oklch(0.511 0.262 276.966)、`chart-2` oklch(0.627 0.194 149.214)、`chart-3` oklch(0.666 0.179 58.318)、`chart-4` oklch(0.577 0.245 27.325)、`chart-5` oklch(0.588 0.158 241.966)、`chart-6`～`chart-10` 依次为紫/玫红/青柠/橙/青绿；对比度 3.06:1～6.46:1，均达到图形对象 3:1 的可辨下限。

深色（400 级，卡片底 oklch 0.205 约 `#171717`）：`chart-1` oklch(0.673 0.182 276.935)、`chart-2` oklch(0.792 0.209 151.711)、`chart-3` oklch(0.828 0.189 84.429)、`chart-4` oklch(0.704 0.191 22.216)、`chart-5` oklch(0.746 0.16 232.661)，`chart-6`～`chart-10` 同系提亮；对比度 5.73:1～11.69:1，深色下清晰可辨。中性色深色下提亮至 `chart-muted` 0.704、`chart-axis` 0.707，避免参考线糊在深底。

## 五、未预料到的情况

1. recharts 公共 chunk 由打包器命名为 `chart-theme-*.js`（389.08 kB），仅文件名变化，体积与拆分逻辑未变。
2. 演示构建中 vite 的 `@vite/client` 请求会被 SPA 重写规则回落为 `index.html`，属正常回落，不影响功能。
3. 登录表单自动化点击偶发失败一次（控制台一度报渲染异常，刷新后无错误），重试即通过，未复现为代码缺陷。
