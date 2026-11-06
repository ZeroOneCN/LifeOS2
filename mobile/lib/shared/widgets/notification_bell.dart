import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';

/// 根页顶栏铃铛：P2 用假未读数，点击进入全局通知中心。
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.unreadCount = 3});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '通知',
      onPressed: () => context.push('/notifications'),
      icon: Badge.count(
        count: unreadCount,
        backgroundColor: context.semanticColors.danger,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
