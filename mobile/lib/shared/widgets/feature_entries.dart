import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// 常用区大卡：比「全部功能」入口更大、更靠上，带一句等宽数字摘要。
///
/// 参数：
/// - [icon]：左侧圆角底图标；
/// - [title]：功能名（与网页端路由标题一致）；
/// - [summary]：一句摘要，数值部分由调用方用 [AppTypography] 等宽样式渲染；
/// - [onTap]：跳转到该功能的真实路由。
class PrimaryFeatureCard extends StatelessWidget {
  const PrimaryFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              Text(title, style: theme.textTheme.titleMedium),
              // 摘要固定一行：1.3x 字号下长金额会换行，导致并排两卡内容高度不齐。
              // 这里用 scaleDown 轻微缩小而不是折行，保证同排卡片对齐。
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    summary,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「全部功能」网格里的紧凑入口：图标 + 功能名，整块可点。
class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            spacing: 10,
            children: <Widget>[
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 两列网格：同一行的卡片等高，文字放大时自动换行而不截断。
class FeatureGrid extends StatelessWidget {
  const FeatureGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      spacing: 12,
      children: <Widget>[
        for (int i = 0; i < children.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                Expanded(child: children[i]),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
