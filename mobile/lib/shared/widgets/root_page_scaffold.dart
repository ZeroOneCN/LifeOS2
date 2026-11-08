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
/// [bottomBar] 用于「保存 / 删除」等主操作：放在 body 的纵向布局里（内容区
/// `Expanded` + 底栏），而不是 `Scaffold.bottomNavigationBar`。这样底栏始终占位，
/// 内容只会在其上方滚动、不会被压住；键盘弹起时 body 整体收缩，底栏随之上移到
/// 键盘上方，最末字段与主操作同时可达。
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
    // 悬浮按钮会盖住内容区最后一行：这里统一预留出按钮高度，
    // 调用方无需再各自算 bottomPadding。
    final double fabInset = floatingActionButton == null ? 0 : 88;
    // 无底栏的页面不再额外留 24dp：这些页面多数嵌在带底部 Tab 的壳里，
    // 再留一次会在内容与 Tab 栏之间露出一条空白（真机实测 72px = 24dp）。
    // 有底栏时保留 12dp 作为按钮的下边距。
    final double contentBottom = (bottomBar == null ? 0 : 12) + fabInset;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, contentBottom),
                child: child,
              ),
            ),
            if (bottomBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                // 统一撑满宽度：单按钮底栏与双按钮底栏左右边界一致。
                child: SizedBox(width: double.infinity, child: bottomBar),
              ),
          ],
        ),
      ),
    );
  }
}
