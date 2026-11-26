import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 指标轨中的单项。
class StatRailItem {
  const StatRailItem({
    required this.label,
    required this.value,
    this.unit,
    this.color,
  });

  final String label;
  final String value;
  final String? unit;

  /// 数值颜色；为空时使用主文字色。
  final Color? color;
}

/// 2.0 指标轨：白底分组卡 + 发丝线分隔，数字等宽右对齐。
///
/// 常见为 3 项；信息较少时允许 2 项，最多 4 项，等宽分配避免数字被挤压。
class StatRail extends StatelessWidget {
  const StatRail({super.key, required this.items})
    : assert(items.length >= 2 && items.length <= 4, '指标轨支持 2~4 项');

  final List<StatRailItem> items;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0)
                Container(
                  width: AppTokens.hairline,
                  color: tokens.line,
                  margin: const EdgeInsets.symmetric(vertical: 11),
                ),
              Expanded(child: _StatCell(item: items[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.item});

  final StatRailItem item;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? unit = item.unit;
    final bool placeholder = item.value == '—' || item.value == '…';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.label,
            // 大字号下「银行卡余额合计」这类标签允许两行，不截断语义。
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.statLabel.copyWith(color: tokens.text2),
          ),
          const SizedBox(height: 4),
          // 金额必须完整可读：三列等宽 + 系统大字号时，等比缩小而不是省略。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: item.value),
                  if (unit != null && unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: AppType.statUnit.copyWith(color: tokens.text2),
                    ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              style: AppType.statValue.copyWith(
                color: item.color ?? (placeholder ? tokens.text3 : tokens.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
