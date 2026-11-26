import 'package:flutter/material.dart';

import '../../core/models/finance_models.dart';
import '../../core/utils/formatters.dart';
import '../../theme/app_tokens.dart';

/// 列表页「加载更多 / 已全部加载」页脚（实现已抽到 shared，这里保留导出，
/// 财务页无需改 import）。
export '../../shared/widgets/list_load_more_footer.dart';

/// 状态色调：统一映射到 2.0 设计令牌里的语义色，避免各页面自己写颜色。
enum StatusTone { info, success, warning, danger }

/// 状态色调 → 前景 / 背景色对。
({Color foreground, Color background}) _toneColors(
  AppTokens tokens,
  StatusTone tone,
) {
  return switch (tone) {
    StatusTone.info => (
      foreground: tokens.accent,
      background: tokens.accent.withValues(alpha: 0.12),
    ),
    StatusTone.success => (
      foreground: tokens.green,
      background: tokens.green.withValues(alpha: 0.14),
    ),
    StatusTone.warning => (
      foreground: tokens.orange,
      background: tokens.orange.withValues(alpha: 0.14),
    ),
    StatusTone.danger => (
      foreground: tokens.red,
      background: tokens.red.withValues(alpha: 0.12),
    ),
  };
}

/// 小状态标签（待还 / 部分还款 / 已结清等），与 [V2Badge] 同一视觉口径。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ({Color foreground, Color background}) colors = _toneColors(
      tokens,
      tone,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppType.badge.copyWith(color: colors.foreground),
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

/// 账单列表行：平台 + 状态 + 到期日 → 剩余金额 + 还款入口。
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
    final AppTokens tokens = AppTokens.of(context);
    final String month = bill.billMonth.length >= 7
        ? bill.billMonth.substring(0, 7)
        : bill.billMonth;
    final bool cleared = bill.status == 'cleared';
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      spacing: 6,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            '$platformName${showMonth ? ' · $month' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.rowTitle.copyWith(
                              color: tokens.text,
                            ),
                          ),
                        ),
                        StatusChip(
                          label: billStatusLabel(bill.status),
                          tone: billTone(bill.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bill.dueDate == null
                          ? '未设置到期日'
                          : '到期 ${formatListDate(bill.dueDate)}'
                              '${bill.overdue ? ' · 已逾期' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(
                        color: bill.overdue ? tokens.red : tokens.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 金额列最多占 2/5 宽；大字号或长金额时整体等比缩小，不截断。
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      // 主数字始终是「剩余」，已结清时是 ¥0.00；
                      // 不加这行小标签会被误读成账单金额变成了 0。
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            if (cleared)
                              TextSpan(
                                text: '剩余 ',
                                style: AppType.rowMeta.copyWith(
                                  color: tokens.text2,
                                ),
                              ),
                            TextSpan(text: formatMoney(bill.remaining)),
                          ],
                        ),
                        maxLines: 1,
                        softWrap: false,
                        style: AppType.rowValue.copyWith(
                          color: cleared ? tokens.text2 : tokens.red,
                        ),
                      ),
                      if (bill.paidAmount > 0) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          '已还 ${formatMoney(bill.paidAmount)}',
                          maxLines: 1,
                          style: AppType.rowMeta.copyWith(color: tokens.text2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (onRepay != null) ...<Widget>[
                const SizedBox(width: 8),
                // 文字按钮而不是纯图标：纯图标既看不出含义，又有误触风险。
                TextButton(
                  onPressed: onRepay,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.accent,
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    textStyle: AppType.action.copyWith(fontSize: 13),
                  ),
                  child: const Text('还款'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「名称 + 金额」聚合明细（按平台 / 分类 / 规划类型）。
///
/// 与 [RecordRow] 同一信息顺序：左名称、右等宽金额；名称单行省略，
/// 金额不换行，适配窄屏与大字号。
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
    final AppTokens tokens = AppTokens.of(context);
    final List<NameAmount> shown = entries.take(maxItems).toList();
    final int rest = entries.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final NameAmount entry in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ),
                const SizedBox(width: 12),
                // 聚合金额同样等比缩小，避免大字号下被裁掉尾数。
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatMoney(entry.amount),
                      maxLines: 1,
                      softWrap: false,
                      style: AppType.rowValue.copyWith(color: tokens.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '其余 $rest 项已省略',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ),
      ],
    );
  }
}
