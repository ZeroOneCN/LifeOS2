import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/app_user.dart';

/// 用户头像：有 `avatar` 时按契约加载（`/` 开头拼服务端 Origin，http 直连），
/// 无头像 / 加载失败时回退到昵称首字或默认人形图标。
///
/// 头像本身不再叠加相机角标：点击语义为「查看大图」，
/// 更换 / 移除入口收在大图页底部，不额外占用设置页版面。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 24,
  });

  final AppUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? url =
        AppScope.of(context).apiClient.resolveAvatar(user?.avatar);

    Widget placeholder = Icon(
      Icons.person_outline,
      size: radius,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final AppUser? current = user;
    if (current != null && current.displayName.isNotEmpty) {
      placeholder = Text(
        String.fromCharCode(current.displayName.runes.first),
        style: theme.textTheme.titleMedium,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: placeholder,
    );
  }
}
