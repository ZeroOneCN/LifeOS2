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

/// 生活中心根页：常用（物品 / 卡片）→ 全部功能 → 生活概览 → 即将到期。
///
/// 摘要数据来自 `GET /lifestyle/overview`（总览层）。
class LifePage extends StatelessWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.overview.lifestyleNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<LifestyleOverview> state =
            scope.overview.lifestyle;
        final LifestyleOverview? data = state.data;
        final List<ExpiringItem> expiring =
            data?.expiringItems ?? const <ExpiringItem>[];

        return RootPageScaffold(
          title: '生活中心',
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
                    icon: Icons.inventory_2_outlined,
                    title: '物品追踪',
                    summary: '在库 ${formatInt(data?.itemInUse)}/'
                        '${formatInt(data?.itemTotal)} 件',
                    onTap: () => context.push('/life/items'),
                  ),
                  PrimaryFeatureCard(
                    icon: Icons.credit_card_outlined,
                    title: '卡片管理',
                    summary: '在册 ${formatInt(data?.cardTotal)} 张',
                    onTap: () => context.push('/life/cards'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '全部功能',
              child: FeatureGrid(
                children: <Widget>[
                  FeatureTile(
                    icon: Icons.description_outlined,
                    title: '生活报告',
                    onTap: () => context.push('/life/reports'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '生活概览',
              child: Row(
                spacing: 16,
                children: <Widget>[
                  Expanded(
                    child: MetricPlaceholder(
                      label: '物品总值',
                      value: formatMoney(data?.itemValue),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '本月扣费',
                      value: formatMoney(data?.monthDeduct),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '30 天内到期',
                      value: formatInt(data?.itemExpiring),
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '即将到期',
              child: expiring.isEmpty
                  ? EmptyState(
                      icon: Icons.timeline_outlined,
                      title: '暂无到期提醒',
                      description: state.status == LoadStatus.unauthenticated
                          ? '登录后展示物品到期提醒'
                          : '30 天内没有即将到期的物品',
                      compact: true,
                    )
                  : Column(
                      spacing: 12,
                      children: <Widget>[
                        for (final ExpiringItem item in expiring)
                          Row(
                            spacing: 12,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                item.daysLeft == null
                                    ? '—'
                                    : '${formatInt(item.daysLeft)} 天',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

