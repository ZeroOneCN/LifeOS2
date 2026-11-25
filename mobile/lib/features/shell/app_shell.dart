import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../theme/app_tokens.dart';

/// 五 Tab 外壳：唯一一级导航。
///
/// - `StatefulShellRoute.indexedStack` 为每个分支保留独立 Navigator 栈；
/// - 切 Tab 只切 index，不重建分支；
/// - 重按当前 Tab → `initialLocation: true` 回到该分支根页（方案要求）；
/// - 底部**图标 + 常驻两字文字**（`labelBehavior: alwaysShow`），
///   375dp 宽下每个 Tab 可用约 59dp，1.0x/1.3x 字号都不会截断或换行；
/// - 切到某个 Tab 时刷新该域总览，避免根页长期停在启动时的旧数据。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 图标 + 两字短标签常驻；`tooltip` 提供全称，长按仍可看到完整定义。
  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite),
          label: '健康',
          tooltip: '健康中心',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: '财务',
          tooltip: '财务中心',
        ),
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '生活',
          tooltip: '生活中心',
        ),
        NavigationDestination(
          icon: Icon(Icons.trending_up),
          label: '投资',
          tooltip: '投资中心',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
          tooltip: '设置',
        ),
      ];

  /// 切 Tab 时刷新该域总览（根页常驻 IndexedStack，不会自动重建）。
  void _refreshOverview(int index) {
    final OverviewController overview = AppScope.of(context).overview;
    switch (index) {
      case 0:
        overview.refreshHealth();
      case 1:
        overview.refreshFinance();
      case 2:
        overview.refreshLifestyle();
      case 3:
        overview.refreshInvestment();
      default:
        break;
    }
  }

  /// 各分支根路由：用于区分「Tab 根页」与「分支内推入的详情页」。
  static const Set<String> _branchRoots = <String>{
    '/health',
    '/finance',
    '/life',
    '/invest',
    '/settings',
  };

  /// 系统返回键统一出口。
  ///
  /// 顺序：先退分支内详情页 → 再回健康首页 → 最后才退出应用。
  /// 这样在任何非健康 Tab 的根页按返回都不会直接退出程序。
  void _handleSystemBack() {
    final GoRouter router = GoRouter.of(context);
    final String path = GoRouterState.of(context).uri.path;
    if (!_branchRoots.contains(path)) {
      // 分支内还有详情 / 表单页：正常回退一级（go_router 会弹出当前分支栈顶）。
      router.pop();
      return;
    }
    if (widget.navigationShell.currentIndex != 0) {
      // 任何 Tab 根页按返回：回到健康首页，而不是退出应用。
      widget.navigationShell.goBranch(0, initialLocation: true);
      _refreshOverview(0);
      return;
    }
    // 已在健康首页：再按一次返回才真正退出。
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // 底栏使用 2.0 的 surface（浅色白 / 深色 #1C1C1E），与页面分组底色分开；
    // 不画顶部分割线，层级只靠 System Blue 选中态表达。
    final AppTokens tokens = AppTokens.of(context);
    return PopScope(
      // 返回键完全由 [_handleSystemBack] 接管，避免根路由直接退出应用。
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: tokens.background,
        body: widget.navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          backgroundColor: tokens.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          destinations: _destinations,
          onDestinationSelected: (int index) {
            widget.navigationShell.goBranch(
              index,
              initialLocation: index == widget.navigationShell.currentIndex,
            );
            _refreshOverview(index);
          },
        ),
      ),
    );
  }
}
