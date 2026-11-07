import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feature_entries.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 健康中心根页：常用（步数 / 用药）→ 全部功能 → 今日用药待办 → 本周概览。
///
/// 摘要数据来自 `GET /health/overview`（总览层）；
/// 7 日均步数单独取 `GET /health/steps/stats?days=7`：
/// 总览里的 `week_summary.steps_avg` 是按「记录条数」平均，
/// 一天有多条分时段记录时会被拉低（实测 1,385 vs 真实日均 4,100），
/// 因此不能直接当「日均」展示。
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  OverviewController? _overview;

  /// 近 7 日日均步数（按天取最大值后平均，口径与步数统计页一致）。
  int? _weekAvgSteps;
  bool _weekStatsLoading = false;
  bool _weekStatsFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final OverviewController overview = AppScope.of(context).overview;
    if (_overview == overview) {
      return;
    }
    _overview?.healthNotifier.removeListener(_onOverviewChanged);
    _overview = overview;
    _overview!.healthNotifier.addListener(_onOverviewChanged);
    // 首次进入时总览可能已就绪（登录后已拉过），补一次 7 日统计。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _weekAvgSteps == null && !_weekStatsLoading) {
        _loadWeekAvg();
      }
    });
  }

  @override
  void dispose() {
    _overview?.healthNotifier.removeListener(_onOverviewChanged);
    super.dispose();
  }

  /// 总览刷新成功（切回健康 Tab / 手动刷新）后同步重算 7 日均步数。
  void _onOverviewChanged() {
    if (!mounted) {
      return;
    }
    final OverviewState<HealthOverview> state = _overview!.health;
    if (state.status == LoadStatus.ready && !_weekStatsLoading) {
      _loadWeekAvg();
    }
  }

  /// 拉近 7 日统计，只取 `avg_steps`；失败时展示 `—`，不回退到总览的错误口径。
  Future<void> _loadWeekAvg() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      return;
    }
    setState(() => _weekStatsLoading = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/steps/stats',
                  queryParameters: <String, dynamic>{'days': 7}))
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
        _weekAvgSteps = StepStats.fromJson(json).avgSteps;
        _weekStatsLoading = false;
        _weekStatsFailed = false;
      });
    } on ApiException {
      if (!mounted) {
        return;
      }
      setState(() {
        _weekStatsLoading = false;
        _weekStatsFailed = true;
      });
    }
  }

  /// 手动刷新：总览 + 7 日均步数。
  void _refresh() {
    final AppScope scope = AppScope.of(context);
    scope.overview.refreshHealth();
    _loadWeekAvg();
  }

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
          actions: <Widget>[
            IconButton(
              tooltip: '刷新步数与用药数据',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
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
                    icon: Icons.directions_walk_outlined,
                    title: '步数统计',
                    summary: _stepsSummary(data),
                    onTap: () async {
                      await context.push('/health/steps');
                      // 从步数页返回：录入可能改变今日步数，重新对账。
                      if (context.mounted) {
                        _refresh();
                      }
                    },
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
              trailing: TextButton(
                onPressed: () => _openMedicationCreate(),
                child: const Text('新增'),
              ),
              child: meds.isEmpty
                  ? EmptyState(
                      icon: Icons.medication_liquid_outlined,
                      title: '今天暂无用药记录',
                      description: state.status == LoadStatus.unauthenticated
                          ? '登录后展示今日待服清单'
                          : '点右上「新增」添加今天的用药计划',
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
                      label: '7 日均步数',
                      value: _weekAvgText(),
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

  /// 打开新增用药页；返回后刷新总览（今日待办与库存会变化）。
  Future<void> _openMedicationCreate() async {
    await context.push('/health/medication/new');
    if (mounted) {
      _refresh();
    }
  }

  /// 步数摘要：总览给的是「最新一条记录」，只有日期是今天才敢写「今日」，
  /// 否则按「最近 MM-dd」展示，避免把昨天的步数当今日。
  String _stepsSummary(HealthOverview? data) {
    final int? steps = data?.steps;
    if (steps == null) {
      return '暂无记录';
    }
    final String date = data?.stepsDate ?? '';
    if (date == _todayText) {
      return '今日 ${formatInt(steps)} 步';
    }
    return '最近 ${_shortDate(date)} · ${formatInt(steps)} 步';
  }

  /// 7 日均步数文案：加载中显示「…」，失败显示「—」（不展示错误口径的数值）。
  String _weekAvgText() {
    if (_weekStatsLoading && _weekAvgSteps == null) {
      return '…';
    }
    if (_weekStatsFailed && _weekAvgSteps == null) {
      return '—';
    }
    return formatInt(_weekAvgSteps);
  }

  static String get _todayText {
    final DateTime now = DateTime.now();
    return '${now.year}-${_two(now.month)}-${_two(now.day)}';
  }

  /// `2026-11-06` → `11-06`；长度异常时原样返回。
  static String _shortDate(String date) {
    return date.length >= 10 ? date.substring(5, 10) : date;
  }

  static String _two(int value) => value < 10 ? '0$value' : '$value';

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
