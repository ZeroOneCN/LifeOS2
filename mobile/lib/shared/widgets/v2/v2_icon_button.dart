import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 2.0 顶部圆形图标按钮：36dp 视觉尺寸 + 系统 48dp 点击区域。
///
/// 视觉上是 iOS 的浅灰圆形按钮，命中区域仍由 [IconButton] 的
/// `MaterialTapTargetSize.padded` 撑到 48dp，满足可访问性要求。
class V2IconButton extends StatelessWidget {
  const V2IconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      iconSize: 18,
      style: IconButton.styleFrom(
        backgroundColor: tokens.fill,
        foregroundColor: tokens.text,
        shape: const CircleBorder(),
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
