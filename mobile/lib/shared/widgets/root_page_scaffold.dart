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
class DetailPageScaffold extends StatelessWidget {
  const DetailPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: child,
        ),
      ),
    );
  }
}
