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
///
/// 所有按钮文字一律单行显示（由 [_ButtonLabel] 统一约束）：
/// 空间不足时整体等比缩小，不折行、不截断，避免并排按钮一侧被挤成两行。
const double kAppButtonHeight = 48;
const double kAppButtonCompactHeight = 36;
const double kAppButtonRadius = AppRadii.control;
const double kAppInlineActionHeight = 36;
const double kAppInlineActionRadius = AppRadii.control;

/// 按钮文字：强制单行。
///
/// `softWrap: false` + `maxLines: 1` 保证永不折行；
/// 外层 `FittedBox(scaleDown)` 在宽度不够时把文字整体等比缩小到一行放得下，
/// 从而「收紧文字」而不是「换行」或「省略号截断」。
class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

/// 主操作按钮：填充主色 + 图标 + 48 高 + 8 圆角。
///
/// [compact] 只缩小高度与内边距（用于确认弹窗与三按钮并列行），
/// 形状、圆角、颜色语义保持一致。
/// [icon] 传 null 时只显示文字，用于 1:1:1 三等宽窄屏，避免图标挤占文字宽度。
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check,
    this.loading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double height = compact ? kAppButtonCompactHeight : kAppButtonHeight;
    final ButtonStyle style = FilledButton.styleFrom(
      minimumSize: Size(compact ? 0 : 64, height),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppButtonRadius),
      ),
    );
    if (icon == null && !loading) {
      return FilledButton(
        onPressed: onPressed,
        style: style,
        child: _ButtonLabel(label),
      );
    }
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: _ButtonLabel(label),
      style: style,
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
            child: _ButtonLabel(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: _ButtonLabel(label),
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
      label: _ButtonLabel(label),
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
      label: _ButtonLabel(label),
    );
  }
}

/// 成对 / 三连操作行：各按钮等分宽度，宽高完全一致（编辑 / 删除的标准布局）。
///
/// [third] 非空时为 1:1:1 三等宽（用于状态页多条修复动作同行）；
/// 窄屏文字余量靠「短文案 + 无图标」保证，不靠缩字号硬塞。
///
/// 确认弹窗也把它包进 `actions`，避免 `AlertDialog` 的 OverflowBar
/// 按文字长度分配宽度（「取消」比「确认移除」短一截）。
class AppActionRow extends StatelessWidget {
  const AppActionRow({
    super.key,
    required this.first,
    required this.second,
    this.third,
  });

  final Widget first;
  final Widget second;
  final Widget? third;

  @override
  Widget build(BuildContext context) {
    // 并列动作统一等宽、等高，避免不同按钮文案导致的视觉失衡。
    return IntrinsicHeight(
      child: Row(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: first),
          Expanded(child: second),
          if (third != null) Expanded(child: third!),
        ],
      ),
    );
  }
}
