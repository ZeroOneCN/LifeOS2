import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';
import '../../theme/app_tokens.dart';

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
      final AppTokens tokens = AppTokens.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.text2,
            ),
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
    final AppTokens tokens = AppTokens.of(context);

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
        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.text2),
      );
      text = '正在加载总览数据…';
    } else if (status == LoadStatus.unauthenticated) {
      leading = Icon(Icons.lock_outline, size: 18, color: tokens.text2);
      text = '未登录，登录后显示真实数据';
      action = _action('登录', () => context.push('/login'), tokens);
    } else if (status == LoadStatus.connectionFailed) {
      leading = Icon(Icons.cloud_off_outlined, size: 18, color: tokens.text2);
      text = '连接失败，已保留登录状态';
      detail = message ?? '请检查服务器地址与网络后重试';
      action = _action('重试', onRetry, tokens);
    } else {
      leading = Icon(Icons.error_outline, size: 18, color: tokens.red);
      text = humanizeApiMessage(message);
      action = _action('重试', onRetry, tokens);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.fill2,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
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
                  style: AppType.rowMeta.copyWith(color: tokens.text2),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: AppType.rowMeta.copyWith(color: tokens.text3),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  /// 状态条内的小操作按钮：System Blue 文字、32 高、不撑开行高。
  Widget _action(String label, VoidCallback onPressed, AppTokens tokens) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: tokens.accent,
        textStyle: AppType.action,
        minimumSize: const Size(44, 32),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }
}
