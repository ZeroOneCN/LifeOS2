import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feature_entries.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_typography.dart';

/// 投资中心根页：持仓概览 → 常用（外汇交易）→ 全部功能 → 交易概览。
///
/// 摘要数据来自 `GET /investment/overview`（总览层）；近一年交易明细不在
/// 总览接口内，明细页留给后续批次。
class InvestPage extends StatelessWidget {
  const InvestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: scope.overview,
      builder: (BuildContext context, _) {
        final OverviewState<InvestmentOverview> state =
            scope.overview.investment;
        final InvestmentOverview? data = state.data;
        final double? netProfit = data?.netProfit;

        return RootPageScaffold(
          title: '投资中心',
          children: <Widget>[
            OverviewStatusBanner(
              status: state.status,
              message: state.message,
              onRetry: scope.overview.refreshInvestment,
            ),
            SectionCard(
              title: '持仓概览',
              child: Row(
                spacing: 24,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: <Widget>[
                        Text(
                          formatMoney(data?.accountValue),
                          style: AppTypography.amountLarge,
                        ),
                        Text(
                          '账户净值',
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
                          formatMoney(netProfit),
                          style: AppTypography.amountLarge.copyWith(
                            color: netProfit == null
                                ? null
                                : (netProfit >= 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error),
                          ),
                        ),
                        Text(
                          '累计盈亏',
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
              title: '常用',
              child: PrimaryFeatureCard(
                icon: Icons.candlestick_chart_outlined,
                title: '外汇交易',
                summary: '近一年 ${formatInt(data?.tradeCount)} 笔 · '
                    '报告 ${formatInt(data?.reportCount)} 份',
                onTap: () => context.push('/invest/forex'),
              ),
            ),
            SectionCard(
              title: '全部功能',
              child: FeatureGrid(
                children: <Widget>[
                  FeatureTile(
                    icon: Icons.description_outlined,
                    title: '投资报告',
                    onTap: () => context.push('/invest/reports'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '交易概览',
              child: Row(
                spacing: 16,
                children: <Widget>[
                  Expanded(
                    child: MetricPlaceholder(
                      label: '胜率',
                      value: formatPercent(data?.winRate),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '持仓中',
                      value: formatInt(data?.openCount),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '交易品种',
                      value: formatInt(data?.symbolCount),
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '近期交易',
              child: EmptyState(
                icon: Icons.show_chart_outlined,
                title: '总览层不含交易明细',
                description: state.status == LoadStatus.unauthenticated
                    ? '登录后展示最近外汇交易'
                    : '交易明细页在后续批次接入',
                compact: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

