import 'package:flutter/material.dart';

/// 空态：图标 + 标题 + 说明，居中。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: <Widget>[
          Icon(icon, size: compact ? 32 : 48, color: muted),
          Text(title, style: theme.textTheme.bodyLarge),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
            ),
            textAlign: TextAlign.center,
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
    final ThemeData theme = Theme.of(context);
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
            style: theme.textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 带说明文字的入口行（指向某个二级页）。
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
