import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// 空态：图标 + 标题 + 说明（+ 可选操作），居中（2.0 字号与灰阶）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.compact = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool compact;

  /// 可选操作文案（如「去新增」）；为空时不显示按钮。
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? action = actionLabel;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: <Widget>[
          Icon(icon, size: compact ? 32 : 48, color: tokens.text3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.rowTitle.copyWith(color: tokens.text),
          ),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
          if (action != null && action.isNotEmpty)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: tokens.accent,
                textStyle: AppType.action,
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }
}

/// 指标占位块：数值 + 标签（数字等宽）。
class MetricPlaceholder extends StatelessWidget {
  const MetricPlaceholder({
    super.key,
    required this.label,
    this.value = '—',
    this.valueColor,
  });

  final String label;
  final String value;

  /// 数值颜色：用于「优惠合计」这类需要语义色的指标。
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: AppType.statValue.copyWith(
              color: valueColor ?? tokens.text,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          style: AppType.statLabel.copyWith(color: tokens.text2),
        ),
      ],
    );
  }
}

/// 带说明文字的入口行（指向某个二级页）。
///
/// 底色、圆角、发丝线由全局 `cardTheme` 提供，与卡片保持同一 2.0 样式。
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// 需要特殊排版（如长地址单行缩放）时直接提供副标题组件。
  final Widget? subtitleWidget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget? subtitleContent =
        subtitleWidget ?? (subtitle == null ? null : Text(subtitle!));
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitleContent,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
