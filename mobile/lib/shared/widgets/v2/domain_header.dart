import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 2.0 域页头：大标题 + 右侧圆形操作按钮。
///
/// 取代旧 `AppBar` 的「标题 + 刷新 + 铃铛」三件套：
/// - 刷新统一走下拽刷新，这里不再出现刷新按钮；
/// - 标题上方不再放日期，保持首屏干净；
/// - 搜索 / 通知由调用方通过 [actions] 传入，保持页头可组合。
class DomainHeader extends StatelessWidget {
  const DomainHeader({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
  });

  /// 域标题，例如「健康」。
  final String title;

  /// 右侧操作按钮（搜索 / 通知等）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.largeTitle.copyWith(color: tokens.text),
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(spacing: 8, children: actions),
            ),
        ],
      ),
    );
  }
}
