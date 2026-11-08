import 'package:flutter/material.dart';

/// 统一的「新增」悬浮按钮：圆形 + 加号。
///
/// 主题里的 `floatingActionButtonTheme` 是圆角矩形，这里显式覆盖为圆形，
/// 让健康中心各记录页的新增入口保持一致。
class AddEntryFab extends StatelessWidget {
  const AddEntryFab({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  /// 无障碍与长按提示文案，例如「新增体检记录」。
  final String tooltip;

  /// 为空时按钮置灰不可点（例如首屏仍在加载）。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      tooltip: tooltip,
      shape: const CircleBorder(),
      onPressed: onPressed,
      child: const Icon(Icons.add),
    );
  }
}
