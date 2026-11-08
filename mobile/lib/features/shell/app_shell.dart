import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    // 底栏与内容同底色、无阴影无描边：层级只靠图标/文字选中态表达，
    // 避免 Tab 上沿出现一条分割线或渐变的“两条”视觉。
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: theme.scaffoldBackgroundColor,
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
    );
  }
}
