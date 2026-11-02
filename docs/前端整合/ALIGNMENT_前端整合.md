# ALIGNMENT — 前端整合（批 3）

## 范围

只改 `frontend/`、`vercel-demo/` 与必要文档（`docs/前端整合/`、`说明文档.md`、`README.md`）。分三块独立提交、各自验证：

1. **路由单一真源**：新建 `frontend/src/config/routes.ts`，路由、侧边导航、面包屑标题共用一张表；管理员守卫由 `adminOnly` 自动派生，删除 `ADMIN_PATHS`；清理 `implementedPages` 中永不生效的死键。
2. **去掉双副本**：mock 层迁入 `frontend/src/demo/`，`main.tsx` 用 `VITE_DEMO=1` 条件动态引入；登录预填与活动日志 `auto` 差异改为运行时开关；最后删除 `vercel-demo/`。
3. **图表语义色**：`index.css` 补深浅两套带色相的 `--chart-1..5` 与状态色；新建 `lib/chart-theme.ts`，替换图表组件的硬编码色值。

## 不做什么

- 不拆分巨型页面（`bills.tsx`、`backup.tsx` 等）。
- 不处理 337 处固定 Tailwind 调色板类（仅处理硬编码 hex）。
- 不改后端、数据库、API 契约。
- 不新增业务功能，不改变现有页面行为、API 调用与可见文案（块 2 两处刻意差异除外）。

## 验收标准

- 每块 `npm run build` 通过；`npm run lint` 告警数不高于 83、错误 0。
- 块 1：非管理员访问所有 `adminOnly` 页面被重定向到 `/home`；`/user-center` 为账户设置页（个人资料与登录账号密码合并后的唯一入口），无侧边导航但可由用户菜单直达，`/user-center/settings` 已重定向到该路径；面包屑与页面标题由路由表统一派生。
- 块 2：`VITE_DEMO=1` 与普通构建各出一份产物，主包体积不因 mock 增大，demo 代码独立 chunk 或 tree-shake；删除 `vercel-demo/` 前先确认演示构建可用。
- 块 3：硬编码 hex 从 69 处降至个位数；深色模式下图表色值可辨（给出取值与对比度判断）。
