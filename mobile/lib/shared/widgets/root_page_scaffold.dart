import 'package:flutter/material.dart';

import 'notification_bell.dart';

/// Tab 根页统一外壳：顶栏（Tab 全称 + 未读铃铛）+ 可滚动内容。
///
/// - 根页拦截系统返回：按方案「根页返回不退出」。
/// - 内容底部留白由调用方控制（带 FAB 的页面传 ≥160）。
class RootPageScaffold extends StatelessWidget {
  const RootPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.floatingActionButton,
    this.bottomPadding = 24,
  });

  final String title;
  final List<Widget> children;

  /// 顶栏额外操作（铃铛固定在最右）。
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: <Widget>[...?actions, const NotificationBell()],
        ),
        floatingActionButton: floatingActionButton,
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// 二级页统一外壳：返回 + 页面标题。
///
/// [bottomBar] 用于「保存 / 删除」等主操作：放在 `bottomNavigationBar` 上，
/// 键盘弹起时由 Scaffold 抬到键盘上方，表单内容滚动时按钮始终可见。
class DetailPageScaffold extends StatelessWidget {
  const DetailPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.floatingActionButton,
    this.actions,
    this.bottomBar,
  });

  final String title;
  final Widget child;
  final Widget? floatingActionButton;

  /// 顶栏操作（如「编辑」）。
  final List<Widget>? actions;

  /// 底部常驻操作区；为空时页面保持无底栏。
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: bottomBar,
              ),
            ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomBar == null ? 24 : 12),
          child: child,
        ),
      ),
    );
  }
}
