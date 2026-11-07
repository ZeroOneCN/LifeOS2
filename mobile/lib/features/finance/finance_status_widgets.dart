import 'package:flutter/material.dart';

import '../../core/models/finance_models.dart';
import '../../core/utils/formatters.dart';
import '../../theme/app_theme.dart';

/// 列表页「加载更多 / 已全部加载」页脚（实现已抽到 shared，这里保留导出，
/// 财务页无需改 import）。
export '../../shared/widgets/list_load_more_footer.dart';

/// 状态色调：统一映射到主题里的语义色，避免各页面自己写颜色。
enum StatusTone { info, success, warning, danger }

/// 小状态标签（待还 / 部分还款 / 已结清等）。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final AppSemanticColors colors = context.semanticColors;
    final Color background;
    final Color foreground;
    switch (tone) {
      case StatusTone.success:
        background = colors.successContainer;
        foreground = colors.onSuccessContainer;
      case StatusTone.warning:
        background = colors.warningContainer;
        foreground = colors.onWarningContainer;
      case StatusTone.danger:
        background = colors.dangerContainer;
        foreground = colors.onDangerContainer;
      case StatusTone.info:
        background = colors.infoContainer;
        foreground = colors.onInfoContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 账单状态 → 色调：待还红、部分还款橙、已结清绿。
StatusTone billTone(String status) {
  switch (status) {
    case 'cleared':
      return StatusTone.success;
    case 'partial':
      return StatusTone.warning;
    default:
      return StatusTone.danger;
  }
}

/// 账单列表行：平台 + 账单月/到期日 + 待还金额 + 状态。
class BillRow extends StatelessWidget {
  const BillRow({
    super.key,
    required this.bill,
    required this.platformName,
    required this.onTap,
    this.onRepay,
    this.showMonth = true,
  });

  final BillItem bill;
  final String platformName;
  final VoidCallback onTap;

  /// 还款入口（列表行，与网页端一致）；已结清时传 null。
  final VoidCallback? onRepay;

  /// 是否在行内显示账单月份；按月分组时传 false，避免与分组头重复。
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String month = bill.billMonth.length >= 7
        ? bill.billMonth.substring(0, 7)
        : bill.billMonth;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Row(
                    spacing: 6,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          '$platformName${showMonth ? ' · $month' : ''}',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StatusChip(
                        label: billStatusLabel(bill.status),
                        tone: billTone(bill.status),
                      ),
                    ],
                  ),
                  Text(
                    bill.dueDate == null
                        ? '未设置到期日'
                        : '到期 ${bill.dueDate}${bill.overdue ? ' · 已逾期' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: bill.overdue ? theme.colorScheme.error : muted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: <Widget>[
                // 主数字始终是「剩余」，已结清时是 ¥0.00；
                // 不加这行小标签会被误读成账单金额变成了 0。
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (bill.status == 'cleared')
                        TextSpan(
                          text: '剩余 ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      TextSpan(text: formatMoney(bill.remaining)),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    color: bill.status == 'cleared' ? muted : null,
                  ),
                ),
                if (bill.paidAmount > 0)
                  Text(
                    '已还 ${formatMoney(bill.paidAmount)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
            if (onRepay != null)
              // 图标 + 文字标签：纯图标既看不出含义，又有误触风险。
              Semantics(
                button: true,
                label: '还款',
                child: InkWell(
                  onTap: onRepay,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.payments_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        Text(
                          '还款',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「名称 + 金额」聚合明细行组（按平台 / 分类 / 规划类型）。
///
/// 金额使用等宽数字且不换行；名称单行省略，适配 375 宽 + 1.3x 字体。
class AmountBreakdownList extends StatelessWidget {
  const AmountBreakdownList({
    super.key,
    required this.entries,
    this.maxItems = 6,
  });

  final List<NameAmount> entries;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final List<NameAmount> shown = entries.take(maxItems).toList();
    final int rest = entries.length - shown.length;
    return Column(
      spacing: 8,
      children: <Widget>[
        for (final NameAmount entry in shown)
          Row(
            spacing: 12,
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              Text(
                formatMoney(entry.amount),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        if (rest > 0)
          Text(
            '其余 $rest 项已省略',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }
}

