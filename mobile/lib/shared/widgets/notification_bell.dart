import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import 'v2/v2_icon_button.dart';

/// 根页顶栏铃铛：显示真实未读数，点击进入通知中心。
///
/// 计数来自 [AppScope.notifications]（全局共用），不是每个铃铛各拉一份：
/// 五个 Tab 的根页都常驻 `IndexedStack`，若各自维护计数，
/// 在通知中心读掉几条后切到另一个 Tab 会看到旧值。
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.compact = false});

  /// 2.0 页头使用：圆形浅灰底按钮，与搜索按钮同尺寸。
  final bool compact;

  /// 进入通知中心；返回后以服务端为准刷新角标（读到通知中心内的本地变更也会先同步）。
  Future<void> _open(BuildContext context) async {
    final AppScope scope = AppScope.of(context);
    await context.push('/notifications');
    if (context.mounted) {
      scope.notifications.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.notifications,
      builder: (BuildContext context, _) {
        final int unread = scope.notifications.count;
        final String tooltip = unread > 0 ? '通知（$unread 条未读）' : '通知';
        final Widget icon = ExcludeSemantics(
          child: Badge.count(
            count: unread,
            isLabelVisible: unread > 0,
            backgroundColor: compact
                ? AppTokens.of(context).red
                : context.semanticColors.danger,
            child: const Icon(Icons.notifications_outlined),
          ),
        );
        if (compact) {
          return V2IconButton(
            tooltip: tooltip,
            onPressed: () => _open(context),
            icon: icon,
          );
        }
        return IconButton(
          tooltip: tooltip,
          onPressed: () => _open(context),
          // 角标只是数字装饰：排除其语义，避免读屏把按钮播报成「86」，
          // 完整信息由 tooltip 提供。
          icon: icon,
        );
      },
    );
  }
}
