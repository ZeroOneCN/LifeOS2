import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/add_record_fab.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feature_entries.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';

/// 财务中心根页：常用（账单 / 债务）→ 全部功能 → 本月概览 → 待还账单。
///
/// 摘要数据来自 `GET /finance/overview`（总览层）。
class FinancePage extends StatelessWidget {
  const FinancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: scope.overview.financeNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<FinanceOverview> state = scope.overview.finance;
        final FinanceOverview? data = state.data;
        final List<PendingBill> bills =
            data?.pendingBills ?? const <PendingBill>[];

        return RootPageScaffold(
          title: '财务中心',
          actions: <Widget>[
            IconButton(
              tooltip: '记一笔',
              icon: const Icon(Icons.edit_note_outlined),
              onPressed: () => showAddRecordSheet(context),
            ),
          ],
          children: <Widget>[
            OverviewStatusBanner(
              status: state.status,
              message: state.message,
              onRetry: scope.overview.retry,
            ),
            SectionCard(
              title: '常用',
              child: FeatureGrid(
                children: <Widget>[
                  PrimaryFeatureCard(
                    icon: Icons.receipt_outlined,
                    title: '账单管理',
                    summary: '待还 ${formatMoney(data?.unpaidBills)}',
                    onTap: () => context.push('/finance/bills'),
                  ),
                  PrimaryFeatureCard(
                    icon: Icons.handshake_outlined,
                    title: '债务管理',
                    summary: '待还 ${formatMoney(data?.outstandingDebt)}',
                    onTap: () => context.push('/finance/debts'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '全部功能',
              child: FeatureGrid(
                children: <Widget>[
                  FeatureTile(
                    icon: Icons.shopping_cart_outlined,
                    title: '购物记录',
                    onTap: () => context.push('/finance/shopping'),
                  ),
                  FeatureTile(
                    icon: Icons.flight_outlined,
                    title: '旅行开支',
                    onTap: () => context.push('/finance/travel'),
                  ),
                  FeatureTile(
                    icon: Icons.gps_fixed_outlined,
                    title: '财务规划',
                    onTap: () => context.push('/finance/planning'),
                  ),
                  FeatureTile(
                    icon: Icons.description_outlined,
                    title: '财务报告',
                    onTap: () => context.push('/finance/reports'),
                  ),
                  FeatureTile(
                    icon: Icons.swap_vert_outlined,
                    title: '流水',
                    onTap: () => context.push('/finance/transactions'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '本月概览',
              child: Row(
                spacing: 24,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: <Widget>[
                        Text(
                          formatMoney(data?.monthExpense),
                          style: AppTypography.amountLarge.copyWith(
                            color: context.semanticColors.danger,
                          ),
                        ),
                        Text(
                          '本月支出',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: <Widget>[
                        Text(
                          formatMoney(data?.unpaidBills),
                          style: AppTypography.amountLarge.copyWith(
                            color: context.semanticColors.warning,
                          ),
                        ),
                        Text(
                          '本月待还',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '待还账单',
              // 根页只展示前 5 条，给一个明确出口，避免用户以为这就是全部。
              trailing: bills.isEmpty
                  ? null
                  : TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => context.push('/finance/bills'),
                      child: const Text('查看全部'),
                    ),
              child: bills.isEmpty
                  ? EmptyState(
                      icon: Icons.inbox_outlined,
                      title: '暂无待还账单',
                      description: state.status == LoadStatus.unauthenticated
                          ? '登录后展示待还账单'
                          : '后端暂无待还账单',
                      compact: true,
                    )
                  : Column(
                      spacing: 12,
                      children: <Widget>[
                        for (final PendingBill bill in bills)
                          _PendingBillRow(bill: bill),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 待还账单单行：名称 + 到期日 + 剩余金额（等宽数字）。
class _PendingBillRow extends StatelessWidget {
  const _PendingBillRow({required this.bill});

  final PendingBill bill;

  /// 账单名里常自带到期日（如「网贷账单-2026-11-08」），
  /// 与下一行「到期 2026-11-08」重复，展示前把后缀日期去掉。
  String get _displayTitle {
    final String? due = bill.dueDate;
    if (due == null || due.isEmpty) {
      return bill.title;
    }
    final String stripped = bill.title
        .replaceAll(RegExp('[\\s·\\-—]*${RegExp.escape(due)}\\s*\$'), '')
        .trim();
    return stripped.isEmpty ? bill.title : stripped;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: 12,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: <Widget>[
              Text(_displayTitle, style: theme.textTheme.bodyMedium),
              if (bill.dueDate != null)
                Text(
                  '到期 ${bill.dueDate}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
        Text(
          formatMoney(bill.remaining),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.semanticColors.danger,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

