import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 全 App 按钮规范（唯一口径，页面不得各写各的）。
///
/// | 语义 | 组件 | 高度 | 圆角 | 颜色 | 图标 |
/// | --- | --- | --- | --- | --- | --- |
/// | 主操作 | [AppPrimaryButton] | 48 | 8 | primary 填充 | 语义图标 |
/// | 次操作 | [AppSecondaryButton] | 48 | 8 | 描边中性色 | 语义图标 |
/// | 危险操作 | [AppDangerButton] | 48 / 紧凑 36 | 8 | 危险色描边 + 危险色文字 | delete_outline |
/// | 区块主操作 | [AppPrimaryAction] | 36 | 8 | primary 实心填充 | add |
///
/// 同一页面里成对出现的「编辑 / 删除」必须放进 [AppActionRow]，
/// 两个按钮各占一半宽度，保证宽高等比。
const double kAppButtonHeight = 48;
const double kAppButtonCompactHeight = 36;
const double kAppButtonRadius = AppRadii.control;
const double kAppInlineActionHeight = 36;
const double kAppInlineActionRadius = AppRadii.control;

/// 主操作按钮：填充主色 + 图标 + 48 高 + 8 圆角。
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, kAppButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kAppButtonRadius),
        ),
      ),
    );
  }
}

/// 次操作按钮：中性描边 + 图标 + 48 高 + 8 圆角。
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double height =
        compact ? kAppButtonCompactHeight : kAppButtonHeight;
    final ButtonStyle style = OutlinedButton.styleFrom(
      minimumSize: Size(0, height),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppButtonRadius),
      ),
    );
    return icon == null
        ? OutlinedButton(
            onPressed: onPressed,
            style: style,
            child: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

/// 危险操作按钮：危险色描边 + 危险色文字，全 App 只有这一种「删除/下线」表现。
///
/// [compact] 只缩小高度与内边距，形状、圆角、颜色语义保持一致。
class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.compact = false,
    this.icon = Icons.delete_outline,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool compact;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final Color danger = Theme.of(context).colorScheme.error;
    final double height =
        compact ? kAppButtonCompactHeight : kAppButtonHeight;
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger,
        side: BorderSide(color: danger.withValues(alpha: 0.55)),
        minimumSize: Size(0, height),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kAppButtonRadius),
        ),
      ),
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// 区块主操作（新增账单 / 新增记录）：主色实心 + 图标 + 36 高 + 8 圆角。
///
/// 它是真正的按钮而不是一行文字：有底色、圆角、图标和按压态；
/// 与主操作按钮使用同一个主题色，仅高度更紧凑以适配列表头部。
class AppPrimaryAction extends StatelessWidget {
  const AppPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        minimumSize: const Size(0, kAppInlineActionHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kAppInlineActionRadius),
        ),
        textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1),
    );
  }
}

/// 成对操作行：两侧各占一半，宽高完全一致（编辑 / 删除的标准布局）。
///
/// 确认弹窗也把它包进 `actions`，避免 `AlertDialog` 的 OverflowBar
/// 按文字长度分配宽度（「取消」比「确认移除」短一截）。
class AppActionRow extends StatelessWidget {
  const AppActionRow({
    super.key,
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: <Widget>[
        Expanded(child: first),
        Expanded(child: second),
      ],
    );
  }
}
