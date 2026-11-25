import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 2.0 徽标色调。
enum V2BadgeTone { info, warn, green, gray }

/// 2.0 小徽标：12/600，6dp 圆角，用于「已服 / 待服 / 剩 6 天」等状态。
class V2Badge extends StatelessWidget {
  const V2Badge(this.label, {super.key, this.tone = V2BadgeTone.gray});

  final String label;
  final V2BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final (Color foreground, Color background) = switch (tone) {
      V2BadgeTone.info => (
        tokens.accent,
        tokens.accent.withValues(alpha: 0.12),
      ),
      V2BadgeTone.warn => (
        tokens.orange,
        tokens.orange.withValues(alpha: 0.14),
      ),
      V2BadgeTone.green => (tokens.green, tokens.green.withValues(alpha: 0.14)),
      V2BadgeTone.gray => (tokens.text2, tokens.fill2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppType.badge.copyWith(color: foreground),
      ),
    );
  }
}

/// 2.0 区块标题：左标题、右文字操作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? action = actionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 7),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.section.copyWith(color: tokens.text2),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: tokens.accent,
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                textStyle: AppType.action,
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }
}

/// 2.0 分组卡：白底 14dp 圆角，行间 0.5dp 发丝线（左缩进 16）。
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // 用 Material 而不是带底色的 Container：让行内 InkWell 的水波纹
    // 画在卡片底色之上，点击才有反馈。
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                height: AppTokens.hairline,
                margin: const EdgeInsets.only(left: 16),
                color: tokens.line,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 2.0 待办行：可选勾选圆点 + 标题/副信息 + 右侧状态。
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? sub = subtitle;
    final Widget? lead = leading;
    final Widget? trail = trailing;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              if (lead != null) ...<Widget>[lead, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    if (sub != null && sub.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowMeta.copyWith(color: tokens.text2),
                      ),
                    ],
                  ],
                ),
              ),
              if (trail != null) ...<Widget>[const SizedBox(width: 12), trail],
            ],
          ),
        ),
      ),
    );
  }
}

/// 2.0 记录行：左侧标题/副信息 + 右侧等宽数值。
class RecordRow extends StatelessWidget {
  const RecordRow({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? sub = subtitle;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    if (sub != null && sub.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowMeta.copyWith(color: tokens.text2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: AppType.rowValue.copyWith(
                  color: valueColor ?? tokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
