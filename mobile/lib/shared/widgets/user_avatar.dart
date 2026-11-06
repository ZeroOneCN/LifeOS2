import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/app_user.dart';

/// 用户头像：有 `avatar` 时按契约加载（`/` 开头拼服务端 Origin，http 直连），
/// 无头像 / 加载失败时回退到昵称首字或默认人形图标。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 24,
    this.showEditBadge = false,
  });

  final AppUser? user;
  final double radius;
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? url = AppScope.of(context).apiClient.resolveAvatar(user?.avatar);

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

    final Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: placeholder,
    );

    if (!showEditBadge) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.surface, width: 2),
            ),
            child: Icon(
              Icons.photo_camera_outlined,
              size: 12,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
