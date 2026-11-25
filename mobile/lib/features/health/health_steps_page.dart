import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_tokens.dart';

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

  /// 当前栏目：0 = 每日，1 = 分时段。
  int _tab = 0;

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

  /// 打开新增步数页；保存成功返回 `true` 后立即重拉统计。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/health/steps/new');
    if (created == true && mounted) {
      _refresh();
    }
  }

  /// 步幅设置：读取当前值，保存后后端会按新步幅重算全部距离。
  Future<void> _openStrideSettings() async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    double? current;
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/steps/settings'))
          .data;
      current = (json?['stride_cm'] as num?)?.toDouble();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('读取步幅失败：${error.message}')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final double? value = await showDialog<double>(
      context: context,
      builder: (BuildContext context) => _StrideDialog(initial: current),
    );
    if (value == null || !mounted) {
      return;
    }
    try {
      await scope.apiClient.put<Map<String, dynamic>>(
        '/health/steps/settings',
        data: <String, dynamic>{'stride_cm': value},
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('已更新步幅，历史距离已重算')));
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('保存失败：${error.message}')));
      }
    }
  }

  /// 点按某一天：打开当天时段明细，逐条进入编辑/删除。
  Future<void> _openDay(String date) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DayPeriodSheet(date: date, onChanged: _refresh),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StepStats? stats = _stats;
    final bool ready =
        _status == LoadStatus.ready || _status == LoadStatus.idle;

    return DetailPageScaffold(
      title: '步数统计',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (!ready || stats == null)
            Expanded(
              child: ListPageBody(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            )
          else ...<Widget>[
            SummaryStrip(
              caption: '近 $_days 天 · 记录 ${formatInt(stats.recordCount)} 条 · '
                  '${stats.maxSteps == null ? '最高单日 —' : '最高单日 ${formatInt(stats.maxSteps)} 步'}',
              items: <StatRailItem>[
                StatRailItem(
                  label: '总步数',
                  value: formatInt(stats.totalSteps),
                  unit: '步',
                ),
                StatRailItem(
                  label: '日均',
                  value: formatInt(stats.avgSteps),
                  unit: stats.avgSteps == null ? null : '步',
                ),
                StatRailItem(
                  label: '记录',
                  value: formatInt(stats.recordCount),
                  unit: '条',
                ),
              ],
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '7 天', value: 7),
                V2SegmentedOption<int>(label: '30 天', value: 30),
                V2SegmentedOption<int>(label: '90 天', value: 90),
              ],
              selected: _days,
              onChanged: _changeRange,
              compact: true,
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '每日', value: 0),
                V2SegmentedOption<int>(label: '分时段', value: 1),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _dailyTab(stats),
                  _periodTab(stats),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 每日栏目：近 14 天走势 + 每日明细 + 步幅设置入口。
  Widget _dailyTab(StepStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    // 走势图与每日明细都只展示最近 14 天，标题按实际展示天数计数。
    final int shownDays = stats.trend.length > 14 ? 14 : stats.trend.length;
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        if (stats.trend.isNotEmpty) ...<Widget>[
          SectionHeader(title: '近 14 天走势 · ${formatInt(shownDays)} 天'),
          GroupCard(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: _TrendBars(trend: stats.trend),
              ),
            ],
          ),
        ],
        SectionHeader(
          title: '每日明细 · 共 ${formatInt(shownDays)} 天',
          actionLabel: '新增步数',
          onAction: _openCreate,
        ),
        GroupCard(
          children: stats.trend.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.directions_walk_outlined,
                    title: '该区间没有步数记录',
                    description: '点「新增步数」录入第一条',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final StepTrendPoint point
                      in stats.trend.reversed.take(14))
                    _DailyRow(point: point, onTap: () => _openDay(point.date)),
                ],
        ),
        GroupCard(
          children: <Widget>[
            V2EntryRow(
              title: '步幅设置',
              subtitle: '修改后按新步幅重算全部历史距离',
              icon: Icons.straighten_outlined,
              onTap: _openStrideSettings,
            ),
          ],
        ),
        Text(
          '仅展示最近 14 天，点按某天可查看并编辑分时段记录。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
      footer: ListLoadMoreFooter(
        loading: false,
        hasMore: false,
        onPressed: _refresh,
      ),
    );
  }

  /// 分时段栏目：区间内各时段累计的进度条。
  Widget _periodTab(StepStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    final List<StepPeriod> periods = stats.byPeriod
        .where((StepPeriod item) => !item.isFull)
        .toList(growable: false);
    final int maxSteps = periods.isEmpty
        ? 0
        : periods
              .map((StepPeriod item) => item.steps)
              .reduce((int a, int b) => a > b ? a : b);
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '分时段累计 · ${formatInt(periods.length)} 段',
          actionLabel: '新增步数',
          onAction: _openCreate,
        ),
        GroupCard(
          children: periods.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.schedule_outlined,
                    title: '暂无分时段数据',
                    description: '该区间没有可展示的时段累计',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final StepPeriod item in periods)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: _PeriodBar(
                          label: item.period,
                          steps: item.steps,
                          maxSteps: maxSteps,
                        ),
                      ),
                    ),
                ],
        ),
        Text(
          '分时段累计不含全天的最终汇总行，避免与各时段重复计算。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }
}

/// 近 14 天柱状图：柱高按最大值等比缩放，底部标注「日」。
class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.trend});

  final List<StepTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
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
          style: AppType.rowMeta.copyWith(color: tokens.text2),
        ),
        SizedBox(
          height: 108,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: <Widget>[
              for (int i = 0; i < points.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: 4,
                    children: <Widget>[
                      Container(
                        height: maxSteps == 0
                            ? 2
                            : (78 * points[i].steps / maxSteps).clamp(2, 78),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(
                            alpha: points[i].steps == maxSteps ? 1 : 0.55,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                      // X 轴默认只显示日；跨月或第一天补「月/日」，
                      // 否则 30 天区间里看不出这几天属于哪个月。
                      // 标签必须固定高度：`FittedBox` 会把「10/1」等比缩小，
                      // 若高度随内容变化，各柱基线就会高低错位。
                      SizedBox(
                        height: 14,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _axisLabel(points, i),
                            maxLines: 1,
                            style: AppType.rowMeta.copyWith(
                              color: tokens.text3,
                              fontSize: 10,
                            ),
                          ),
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

  /// 柱状图 X 轴标签：默认只显示「日」；首根与跨月的那根补「月/日」。
  ///
  /// 只显示日号时，跨月（如 `31 → 01`）无法判断属于哪个月；在月份切换处
  /// 标出月份即可，其余标签保持简短，14 根柱子也不会挤在一起。
  String _axisLabel(List<StepTrendPoint> points, int index) {
    final String date = points[index].date;
    if (date.length < 10) {
      return date;
    }
    final bool first = index == 0;
    final String previous = first ? '' : points[index - 1].date;
    final bool monthChanged = previous.length >= 7 &&
        previous.substring(0, 7) != date.substring(0, 7);
    if (first || monthChanged) {
      final int month = int.tryParse(date.substring(5, 7)) ?? 0;
      final int day = int.tryParse(date.substring(8, 10)) ?? 0;
      return '$month/$day';
    }
    return date.substring(8, 10);
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
    final AppTokens tokens = AppTokens.of(context);
    final double fraction = maxSteps == 0 ? 0 : steps / maxSteps;
    return Row(
      spacing: 10,
      children: <Widget>[
        SizedBox(
          width: 54,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 6,
              backgroundColor: tokens.fill2,
              color: tokens.accent,
            ),
          ),
        ),
        SizedBox(
          width: 68,
          child: Text(
            formatInt(steps),
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            style: AppType.rowMeta.copyWith(
              color: tokens.text,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 每日明细行：日期 + 步数 + 距离/热量；点按进入当天时段明细。
class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.point, required this.onTap});

  final StepTrendPoint point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
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
                      formatListDate(point.date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${point.distanceKm.toStringAsFixed(2)} km · '
                      '${formatInt(point.calories)} 千卡',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatInt(point.steps),
                maxLines: 1,
                softWrap: false,
                style: AppType.rowValue.copyWith(color: tokens.text),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当天时段明细弹层：列出该日每条 `health_steps` 记录，点按进入编辑。
///
/// 数据：`GET /health/steps?start=date&end=date`（返回含 id，可直接编辑/删除）。
class _DayPeriodSheet extends StatefulWidget {
  const _DayPeriodSheet({required this.date, required this.onChanged});

  final String date;

  /// 编辑/删除成功后通知父页面重拉统计（总览、日均、时段分布一起刷新）。
  final VoidCallback onChanged;

  @override
  State<_DayPeriodSheet> createState() => _DayPeriodSheetState();
}

class _DayPeriodSheetState extends State<_DayPeriodSheet> {
  List<StepRecord>? _records;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  /// 按日期拉取时段记录；时段按时间先后排序，`full`（全天累计）排最后。
  Future<void> _load() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/steps', queryParameters: {
        'start': widget.date,
        'end': widget.date,
        'page_size': 100,
      }))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '时段记录返回为空',
        );
      }
      final List<StepRecord> records =
          ((json['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map item) =>
                  StepRecord.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false);
      records.sort((StepRecord a, StepRecord b) {
        if (a.isFull != b.isFull) {
          return a.isFull ? 1 : -1;
        }
        return a.period.compareTo(b.period);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _records = records;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  /// 进入编辑页；保存或删除返回 `true` 后刷新本弹层与页面统计。
  Future<void> _openEdit(StepRecord record) async {
    final bool? changed = await context.push<bool>(
      '/health/steps/${record.id}',
      extra: record,
    );
    if (!mounted || changed != true) {
      return;
    }
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final List<StepRecord>? records = _records;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: <Widget>[
            Text(
              '${widget.date} 时段明细',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              '点按任意时段可修改步数/时段，或删除该记录。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  spacing: 8,
                  children: <Widget>[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    AppSecondaryButton(
                      label: '重试',
                      compact: true,
                      onPressed: _load,
                    ),
                  ],
                ),
              )
            else if (records == null || records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyState(
                  icon: Icons.directions_walk_outlined,
                  title: '当天没有时段记录',
                  description: '可在步数页「新增步数」补录',
                  compact: true,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final StepRecord record = records[index];
                    return _PeriodRecordRow(
                      record: record,
                      onTap: () => _openEdit(record),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 弹层里的单条时段记录行：时段 + 步数 + 距离，尾部编辑箭头。
class _PeriodRecordRow extends StatelessWidget {
  const _PeriodRecordRow({required this.record, required this.onTap});

  final StepRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Text(
                    stepPeriodLabel(record.period),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: record.isFull ? FontWeight.w600 : null,
                    ),
                  ),
                  Text(
                    '${record.distanceKm.toStringAsFixed(2)} km · '
                    '${formatInt(record.calories)} 千卡',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Text(
              '${formatInt(record.steps)} 步',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

/// 步幅设置对话框：只提交 `stride_cm`，单位厘米。
class _StrideDialog extends StatefulWidget {
  const _StrideDialog({this.initial});

  final double? initial;

  @override
  State<_StrideDialog> createState() => _StrideDialogState();
}

class _StrideDialogState extends State<_StrideDialog> {
  late final TextEditingController _value = TextEditingController(
    text: widget.initial == null
        ? ''
        : (widget.initial == widget.initial!.roundToDouble()
            ? widget.initial!.toStringAsFixed(0)
            : '${widget.initial}'),
  );
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('步幅设置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: <Widget>[
          const Text('步幅用于按步数换算距离；保存后后端会重算全部历史距离。'),
          TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '步幅（厘米）',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        AppActionRow(
          first: AppSecondaryButton(
            label: '取消',
            compact: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          second: AppPrimaryButton(
            label: '保存',
            compact: true,
            onPressed: () {
              final double? value = double.tryParse(_value.text.trim());
              if (value == null || value < 0) {
                setState(() => _error = '请填写不小于 0 的步幅');
                return;
              }
              Navigator.of(context).pop(value);
            },
          ),
        ),
      ],
    );
  }
}
