import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 步数统计：区间汇总 + 每日趋势柱状图 + 分时段累计。
///
/// 数据：`GET /health/steps/stats?days=`（7/30/90 可切换）。
class HealthStepsPage extends StatefulWidget {
  const HealthStepsPage({super.key});

  @override
  State<HealthStepsPage> createState() => _HealthStepsPageState();
}

class _HealthStepsPageState extends State<HealthStepsPage> {
  int _days = 30;
  StepStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  @override
  void initState() {
    super.initState();
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 按当前区间拉统计；切换区间时保留旧数据避免整页闪烁。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _status = scope.auth.connectionFailed
            ? LoadStatus.connectionFailed
            : LoadStatus.unauthenticated;
        _message = scope.auth.restoreError;
      });
      return;
    }
    setState(() {
      _status = _stats == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/steps/stats',
                  queryParameters: <String, dynamic>{'days': _days}))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '步数统计返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = StepStats.fromJson(json);
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final bool offline = scope.auth.hasLocalSession &&
          (error.kind == ApiErrorKind.network ||
              error.kind == ApiErrorKind.timeout);
      setState(() {
        _status = error.isUnauthorized
            ? LoadStatus.unauthenticated
            : (offline ? LoadStatus.connectionFailed : LoadStatus.failed);
        _message = error.message;
      });
    }
  }

  /// 切换统计区间（7 / 30 / 90 天）。
  void _changeRange(int days) {
    if (days == _days) {
      return;
    }
    setState(() => _days = days);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StepStats? stats = _stats;

    return DetailPageScaffold(
      title: '步数统计',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 7, label: Text('7 天')),
                  ButtonSegment<int>(value: 30, label: Text('30 天')),
                  ButtonSegment<int>(value: 90, label: Text('90 天')),
                ],
                selected: <int>{_days},
                showSelectedIcon: false,
                onSelectionChanged: (Set<int> selection) =>
                    _changeRange(selection.first),
              ),
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '区间汇总',
                  trailing: Text(
                    '记录 ${stats.recordCount} 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: MetricPlaceholder(
                              label: '总步数',
                              value: formatInt(stats.totalSteps),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '日均',
                              value: stats.avgSteps == null
                                  ? '—'
                                  : formatInt(stats.avgSteps!),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '最高单日',
                              value: stats.maxSteps == null
                                  ? '—'
                                  : formatInt(stats.maxSteps!),
                            ),
                          ),
                        ],
                      ),
                      if (stats.trend.isEmpty)
                        const EmptyState(
                          icon: Icons.directions_walk_outlined,
                          title: '该区间没有步数记录',
                          description: '换一个时间区间或先在网页端导入步数',
                          compact: true,
                        )
                      else
                        _TrendBars(trend: stats.trend),
                    ],
                  ),
                ),
                if (stats.byPeriod.any((StepPeriod item) => !item.isFull))
                  SectionCard(
                    title: '分时段累计',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: <Widget>[
                        for (final StepPeriod item
                            in stats.byPeriod.where(
                                (StepPeriod value) => !value.isFull))
                          _PeriodBar(
                            label: item.period,
                            steps: item.steps,
                            maxSteps: stats.byPeriod
                                .where((StepPeriod value) => !value.isFull)
                                .map((StepPeriod value) => value.steps)
                                .reduce((int a, int b) => a > b ? a : b),
                          ),
                      ],
                    ),
                  ),
                SectionCard(
                  title: '每日明细',
                  trailing: Text(
                    '最近 ${stats.trend.length > 14 ? 14 : stats.trend.length} 天',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: stats.trend.isEmpty
                      ? const EmptyState(
                          icon: Icons.directions_walk_outlined,
                          title: '暂无每日数据',
                          description: '该区间没有步数记录',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final StepTrendPoint point
                                in stats.trend.reversed.take(14))
                              _DailyRow(point: point),
                          ],
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 近 14 天柱状图：柱高按最大值等比缩放，底部标注「日」。
class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.trend});

  final List<StepTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<StepTrendPoint> points =
        trend.length > 14 ? trend.sublist(trend.length - 14) : trend;
    final int maxSteps = points
        .map((StepTrendPoint point) => point.steps)
        .reduce((int a, int b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Text(
          '近 ${points.length} 天走势（最高 ${formatInt(maxSteps)} 步）',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(
          height: 108,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: <Widget>[
              for (final StepTrendPoint point in points)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: 4,
                    children: <Widget>[
                      Container(
                        height: maxSteps == 0
                            ? 2
                            : (78 * point.steps / maxSteps).clamp(2, 78),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: point.steps == maxSteps ? 1 : 0.55,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                      Text(
                        point.date.length >= 10
                            ? point.date.substring(8, 10)
                            : point.date,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 分时段进度条：条形长度按时段最大值等比。
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.label,
    required this.steps,
    required this.maxSteps,
  });

  final String label;
  final int steps;
  final int maxSteps;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double fraction = maxSteps == 0 ? 0 : steps / maxSteps;
    return Row(
      spacing: 10,
      children: <Widget>[
        SizedBox(
          width: 54,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            formatInt(steps),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 每日明细行：日期 + 步数 + 距离/热量。
class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.point});

  final StepTrendPoint point;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(point.date, style: theme.textTheme.bodyMedium),
                Text(
                  '${point.distanceKm.toStringAsFixed(2)} km · '
                  '${point.calories.toStringAsFixed(1)} kcal',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          Text(
            formatInt(point.steps),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
