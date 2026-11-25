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
  });

  final String label;
  final String value;
  final String? unit;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? unitText = unit;
    final String? subtitleText = subtitle;
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
          Text.rich(
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
            overflow: TextOverflow.ellipsis,
            style: AppType.hero.copyWith(color: tokens.text),
          ),
          if (subtitleText != null && subtitleText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              subtitleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.heroSub.copyWith(color: tokens.text2),
            ),
          ],
        ],
      ),
    );
  }
}
