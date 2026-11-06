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

/// 健康中心根页：常用（步数 / 用药）→ 全部功能 → 今日用药待办 → 本周概览。
///
/// 摘要数据来自 `GET /health/overview`（总览层），列表页仍走占位。
class HealthPage extends StatelessWidget {
  const HealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.overview.healthNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<HealthOverview> state = scope.overview.health;
        final HealthOverview? data = state.data;
        final List<MedicationItem> meds =
            data?.medicationItems ?? const <MedicationItem>[];

        return RootPageScaffold(
          title: '健康中心',
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
                    icon: Icons.directions_walk_outlined,
                    title: '步数统计',
                    summary: '今日 ${formatInt(data?.steps)} 步',
                    onTap: () => context.push('/health/steps'),
                  ),
                  PrimaryFeatureCard(
                    icon: Icons.medication_outlined,
                    title: '用药跟踪',
                    summary: '今日 ${formatInt(data?.pendingCount)} 项待服',
                    onTap: () => context.push('/health/medication'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '全部功能',
              child: FeatureGrid(
                children: <Widget>[
                  FeatureTile(
                    icon: Icons.bedtime_outlined,
                    title: '睡眠体征',
                    onTap: () => context.push('/health/vitals-sleep'),
                  ),
                  FeatureTile(
                    icon: Icons.fitness_center_outlined,
                    title: '健身运动',
                    onTap: () => context.push('/health/fitness'),
                  ),
                  FeatureTile(
                    icon: Icons.assignment_outlined,
                    title: '体检指标',
                    onTap: () => context.push('/health/checkup'),
                  ),
                  FeatureTile(
                    icon: Icons.description_outlined,
                    title: '健康报告',
                    onTap: () => context.push('/health/reports'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '今日用药待办',
              child: meds.isEmpty
                  ? EmptyState(
                      icon: Icons.medication_liquid_outlined,
                      title: '今天暂无用药记录',
                      description: state.status == LoadStatus.unauthenticated
                          ? '登录后展示今日待服清单'
                          : '后端暂无今日用药数据',
                      compact: true,
                    )
                  : Column(
                      spacing: 12,
                      children: <Widget>[
                        for (final MedicationItem item in meds)
                          _MedicationRow(item: item),
                      ],
                    ),
            ),
            SectionCard(
              title: '本周概览',
              child: Row(
                spacing: 16,
                children: <Widget>[
                  Expanded(
                    child: MetricPlaceholder(
                      label: '日均步数',
                      value: formatInt(data?.weekStepsAvg),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '平均睡眠',
                      value: _sleepText(data?.weekSleepAvgMin),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '运动次数',
                      value: formatInt(data?.weekFitnessCount),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 周平均睡眠：分钟 → `7.5h`；无数据返回 `--`。
  static String _sleepText(int? minutes) {
    if (minutes == null) {
      return '--';
    }
    return '${(minutes / 60).toStringAsFixed(1)}h';
  }
}

/// 今日用药单行：药名 + 剂量 + 已服/待服标记。
class _MedicationRow extends StatelessWidget {
  const _MedicationRow({required this.item});

  final MedicationItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: 10,
      children: <Widget>[
        Icon(
          item.taken ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: item.taken ? theme.colorScheme.primary : muted,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: <Widget>[
              Text(item.name, style: theme.textTheme.bodyMedium),
              if (item.dosage != null && item.dosage!.isNotEmpty)
                Text(
                  item.dosage!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
        Text(
          item.taken ? '已服' : '待服',
          style: theme.textTheme.bodySmall?.copyWith(
            color: item.taken ? theme.colorScheme.primary : muted,
          ),
        ),
      ],
    );
  }
}

