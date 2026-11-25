# LifeOS Mobile

LifeOS 2.0 的 Flutter 移动端，与网页端共用同一个后端（FastAPI，默认 `http://<服务器IP>:9515/api/v1`）。

## 技术栈

- Flutter 3 + Dart 3，状态管理使用项目内 `AppScope`（InheritedNotifier + ChangeNotifier）
- 网络：Dio（access/refresh 双令牌，401 自动刷新并重放）
- 路由：go_router，`StatefulShellRoute.indexedStack` 五个根分支
- 本地存储：shared_preferences（界面偏好）+ flutter_secure_storage（令牌）
- 图表：自绘 `CustomPainter` / 轻量组件，不引第三方图表库

## 目录

```
lib/
├── core/            # 路由、网络、模型、鉴权、概览数据
├── features/        # 按域划分：health / finance / life / invest / reports / settings / notifications / shell
├── shared/widgets/  # 通用组件；v2/ 为 2.0 页面套件
└── theme/           # AppTokens（颜色/圆角/间距）与 AppType（字号）
```

## 2.0 页面规范

- 页面骨架：`DetailPageScaffold` + `ListPageBody`（状态 → 摘要 → 分组 → 页脚）
- 信息顺序：`SummaryStrip`（2~4 项指标）→ `SectionHeader`（标题 + 数量 + 操作）→ `GroupCard` 行 → 页尾说明
- 栏目切换用 `V2Segmented` + `IndexedStack`，在 Tab 内就地切换，不跳页
- 颜色与字号统一取 `AppTokens.of(context)` / `AppType`，深浅色跟随系统；不提供外观/字体设置
- 返回键：详情页回上一级；任意非健康 Tab 根页回健康首页；健康概览再按一次退出应用

## 本地运行

```bash
flutter pub get
flutter run -d <device-id>          # 真机/模拟器
flutter analyze lib                 # 静态检查，目标 0 问题
flutter test                        # 单元测试
flutter build apk --debug           # 调试包
```

后端地址在 App「设置 → 服务器地址」中配置，需与网页端指向同一实例。

## 已知事项

- 体检单位历史截断已通过后端迁移修复（`b7e1c5d9a2f4`、`c8a4f1d2e6b7`）；长单位在列表按「数值一行、单位一行」显示。
- 财务报告历史快照中的购物明细已由迁移 `d3f6a8b1c4e2` 重建（平台名、单价空值、补全 104 笔），新报告由修正后的生成器产出。
- UI 审计（2026-11-08）的 P0 / P1 / P2 / P3 共 53 条已全部闭环；逐条处理结果见 `docs/移动端可行性研究/UI_AUDIT_2026-11-08.md` 文末。
- 账户设置：资料编辑留在账户页并用底栏保存，修改密码进入独立子页 `/settings/account/password`；登录设备列表展示脱敏 IP。
- 蓝牙体脂秤工具页（`health_body_ble_page.dart`）与登录页品牌样式为有意保留，未纳入 2.0 页面套件。
