import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 2.0 首屏 Hero：一行标签 + 一个大号等宽数字 + 一句副信息。
///
/// 只承载「今天最关键的一个数」，不再叠加卡片边框；数字统一使用
/// tabular figures，跨页面刷新时不会左右跳动。
class HeroMetric extends StatelessWidget {
  const HeroMetric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.subtitleColor,
  });

  final String label;
  final String value;
  final String? unit;
  final String? subtitle;

  /// 副信息颜色；默认次要文字色，投资域用它表达盈亏红绿。
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? unitText = unit;
    final String? subtitleText = subtitle;
    // 空值用较浅、较小的占位样式：48px 粗体「—」在真机上像一条黑杠。
    final bool placeholder = value == '—' || value == '…';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
          const SizedBox(height: 5),
          // 首屏大数字同样不能被截断：宽度不足时整体等比缩小。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: value),
                  if (unitText != null && unitText.isNotEmpty)
                    TextSpan(
                      text: ' $unitText',
                      style: AppType.heroUnit.copyWith(color: tokens.text2),
                    ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              style: placeholder
                  ? AppType.largeTitle.copyWith(color: tokens.text3)
                  : AppType.hero.copyWith(color: tokens.text),
            ),
          ),
          if (subtitleText != null && subtitleText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              subtitleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.heroSub.copyWith(
                color: subtitleColor ?? tokens.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
