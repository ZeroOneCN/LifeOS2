import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/storage/preferences_service.dart';

/// 五 Tab 外壳：唯一一级导航。
///
/// - `StatefulShellRoute.indexedStack` 为每个分支保留独立 Navigator 栈；
/// - 切 Tab 只切 index，不重建分支；
/// - 重按当前 Tab → `initialLocation: true` 回到该分支根页（方案要求）；
/// - 底部常态只显示图标（`labelBehavior: alwaysHide`），长按图标时由
///   [NavigationDestination.tooltip] 弹出该 Tab 全称；
/// - 首次进入时给一次轻提示「长按图标可看名称」，持久化后不再出现。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 图标常显、文字隐藏；`tooltip` 提供长按时的全称。
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

  bool _showHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowHint());
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  /// 只在首次进入时展示一次「长按看名称」的轻提示（不弹模态）。
  void _maybeShowHint() {
    if (!mounted) {
      return;
    }
    final PreferencesService prefs = AppScope.of(context).preferences;
    if (prefs.tabHintShown) {
      return;
    }
    prefs.markTabHintShown();
    setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(seconds: 6), _hideHint);
  }

  void _hideHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
    if (mounted && _showHint) {
      setState(() => _showHint = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          widget.navigationShell,
          if (_showHint)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: _TabHintBanner(onClose: _hideHint),
            ),
        ],
      ),
      bottomNavigationBar: TooltipTheme(
        data: const TooltipThemeData(
          // 长按约 400ms 出气泡；松手后 350ms 内消失，避免气泡挡住内容。
          waitDuration: Duration(milliseconds: 400),
          showDuration: Duration(milliseconds: 350),
          exitDuration: Duration(milliseconds: 80),
        ),
        child: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
          destinations: _destinations,
          onDestinationSelected: (int index) {
            widget.navigationShell.goBranch(
              index,
              initialLocation: index == widget.navigationShell.currentIndex,
            );
          },
        ),
      ),
    );
  }
}

/// 一次性轻提示：说明「长按图标可看名称」。
class _TabHintBanner extends StatelessWidget {
  const _TabHintBanner({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          spacing: 8,
          children: <Widget>[
            Icon(
              Icons.touch_app_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Expanded(
              child: Text(
                '长按底部图标可查看 Tab 名称',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: '知道了',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
