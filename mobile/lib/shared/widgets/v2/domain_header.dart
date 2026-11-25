import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 2.0 域页头：日期 + 大标题 + 右侧圆形操作按钮。
///
/// 取代旧 `AppBar` 的「标题 + 刷新 + 铃铛」三件套：
/// - 刷新统一走下拽刷新，这里不再出现刷新按钮；
/// - 搜索 / 通知由调用方通过 [actions] 传入，保持页头可组合。
class DomainHeader extends StatelessWidget {
  const DomainHeader({
    super.key,
    required this.title,
    required this.date,
    this.actions = const <Widget>[],
  });

  /// 域标题，例如「健康」。
  final String title;

  /// 日期副标题，例如「11月25日 星期二」。
  final String date;

  /// 右侧操作按钮（搜索 / 通知等）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 2, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.date.copyWith(color: tokens.text2),
                ),
                const SizedBox(height: 1),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.largeTitle.copyWith(color: tokens.text),
                  ),
                ),
              ],
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

/// 页头日期文案：`11月25日 星期二`。
///
/// 不引 `intl`，避免为一行日期新增依赖；星期按周一到周日映射。
String formatDomainDate(DateTime date) {
  const List<String> weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${date.month}月${date.day}日 星期${weekdays[date.weekday - 1]}';
}
