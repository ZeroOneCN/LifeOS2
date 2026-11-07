import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';

/// 业务列表页的状态占位：加载中 / 失败 / 连接失败 / 未登录。
///
/// [LoadStatus.ready] / [LoadStatus.idle] 时不占位（由调用方渲染列表或空态）。
class ListStatusView extends StatelessWidget {
  const ListStatusView({
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
    if (status == LoadStatus.idle || status == LoadStatus.ready) {
      return const SizedBox.shrink();
    }
    if (status == LoadStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final bool unauthenticated = status == LoadStatus.unauthenticated;
    final bool connectionFailed = status == LoadStatus.connectionFailed;
    return OverviewStatusBanner(
      status: unauthenticated
          ? LoadStatus.unauthenticated
          : (connectionFailed ? LoadStatus.connectionFailed : LoadStatus.failed),
      message: message,
      onRetry: onRetry,
    );
  }
}

/// 总览状态条：把「加载中 / 请求失败 / 未登录 / 连接失败」显性化，放在每个 Tab 根页顶部。
///
/// - [LoadStatus.ready] / [LoadStatus.idle] 时不占位；
/// - 失败给「重试」，未登录给「登录」（进入 `/login`）；
/// - 连接失败（有令牌但网络不可达）给「重试」，并明确「已保留登录状态」，
///   不把用户踢回登录页。
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
    String? detail;
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
    } else if (status == LoadStatus.connectionFailed) {
      leading = Icon(Icons.cloud_off_outlined, size: 18, color: muted);
      text = '连接失败，已保留登录状态';
      detail = message ?? '请检查服务器地址与网络后重试';
      action = TextButton(onPressed: onRetry, child: const Text('重试'));
    } else {
      leading = Icon(
        Icons.error_outline,
        size: 18,
        color: theme.colorScheme.error,
      );
      text = humanizeApiMessage(message);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
