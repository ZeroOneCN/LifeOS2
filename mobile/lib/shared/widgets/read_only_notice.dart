import 'package:flutter/material.dart';

/// 只读页说明条：明确当前页面仅支持查看，避免出现点了没反应的按钮。
class ReadOnlyNotice extends StatelessWidget {
  const ReadOnlyNotice({
    super.key,
    this.text = '当前版本仅支持查看，记录请在网页端添加。',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 8,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: muted),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
