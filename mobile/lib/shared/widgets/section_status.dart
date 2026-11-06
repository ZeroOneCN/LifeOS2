import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/overview_controller.dart';

/// 总览状态条：把「加载中 / 请求失败 / 未登录」显性化，放在每个 Tab 根页顶部。
///
/// - [LoadStatus.ready] / [LoadStatus.idle] 时不占位；
/// - 失败给「重试」，未登录给「登录」（进入 `/login`）。
class OverviewStatusBanner extends StatelessWidget {
  const OverviewStatusBanner({
    super.key,
    required this.status,
    this.message,
    required this.onRetry,
  });

  final LoadStatus status;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;

    if (status == LoadStatus.idle || status == LoadStatus.ready) {
      return const SizedBox.shrink();
    }

    Widget leading;
    String text;
    Widget? action;
    if (status == LoadStatus.loading) {
      leading = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: muted),
      );
      text = '正在加载总览数据…';
    } else if (status == LoadStatus.unauthenticated) {
      leading = Icon(Icons.lock_outline, size: 18, color: muted);
      text = '未登录，登录后显示真实数据';
      action = TextButton(
        onPressed: () => context.push('/login'),
        child: const Text('登录'),
      );
    } else {
      leading = Icon(
        Icons.error_outline,
        size: 18,
        color: theme.colorScheme.error,
      );
      text = message ?? '加载失败，请重试';
      action = TextButton(onPressed: onRetry, child: const Text('重试'));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 8,
        children: <Widget>[
          leading,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

