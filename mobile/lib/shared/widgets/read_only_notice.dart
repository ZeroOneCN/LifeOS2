import 'package:flutter/material.dart';

/// 只读页说明条：说明数据来源，避免出现点了没反应的按钮。
class ReadOnlyNotice extends StatelessWidget {
  const ReadOnlyNotice({
    super.key,
    this.text = '以下记录同步自服务端，这里展示统计与明细。',
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
