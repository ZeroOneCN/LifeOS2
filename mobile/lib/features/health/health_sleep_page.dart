import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/read_only_notice.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 睡眠体征：累计概览 + 分阶段均值 + 睡眠记录分页（只读）。
///
/// 数据：
/// - `GET /health/vitals-sleep/stats?days=0`
/// - `GET /health/vitals-sleep?page=&page_size=20`
///
/// 深睡/浅睡/醒来次数/质量等字段可能未采集，一律显示「—」而不是 0。
class HealthSleepPage extends StatefulWidget {
  const HealthSleepPage({super.key});

  @override
  State<HealthSleepPage> createState() => _HealthSleepPageState();
}

class _HealthSleepPageState extends State<HealthSleepPage> {
  final List<SleepRecord> _items = <SleepRecord>[];

  SleepStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

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

  /// 首屏/重试：并行拉统计与第一页记录，任一失败整体失败。
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
      final List<Map<String, dynamic>?> responses =
          await Future.wait(<Future<Map<String, dynamic>?>>[
        scope.apiClient
            .get<Map<String, dynamic>>(
              '/health/vitals-sleep/stats',
              queryParameters: <String, dynamic>{'days': 0},
            )
            .then((value) => value.data),
        scope.apiClient
            .get<Map<String, dynamic>>(
              '/health/vitals-sleep',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
            )
            .then((value) => value.data),
      ]);
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '睡眠接口返回数据为空',
        );
      }
      final List<SleepRecord> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = SleepStats.fromJson(statsJson);
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _total = (listJson['total'] as num?)?.toInt() ?? items.length;
        _hasMore = _items.length < _total;
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

  /// 加载更多睡眠记录；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/vitals-sleep',
                  queryParameters: <String, dynamic>{
            'page': _page + 1,
            'page_size': 20,
          }))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _page += 1;
        _items.addAll(_parseItems(json));
        _total = (json['total'] as num?)?.toInt() ?? _items.length;
        _hasMore = _items.length < _total;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载更多失败：${error.message}')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 从分页响应中取出 `items` 并转为 [SleepRecord]。
  List<SleepRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => SleepRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final SleepStats? stats = _stats;

    return DetailPageScaffold(
      title: '睡眠体征',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              const ReadOnlyNotice(),
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '睡眠概览',
                  trailing: Text(
                    '记录 ${stats.recordCount} 条',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: Row(
                    spacing: 16,
                    children: <Widget>[
                      Expanded(
                        child: MetricPlaceholder(
                          label: '平均时长',
                          value: formatDuration(stats.avgDurationMin),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '平均质量',
                          value: stats.avgQuality == null
                              ? '—'
                              : '${formatOneDecimal(stats.avgQuality)} / 10',
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '记录条数',
                          value: formatInt(stats.recordCount),
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '分阶段睡眠',
                  child: stats.hasStageData
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: <Widget>[
                            _StageRow(label: '深睡', minutes: stats.avgDeepMin),
                            _StageRow(label: '浅睡', minutes: stats.avgLightMin),
                            Text(
                              '分阶段时长由设备上报，未采集时显示「—」。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        )
                      : const EmptyState(
                          icon: Icons.bedtime_outlined,
                          title: '暂无分阶段数据',
                          description: '当前记录未上报深睡/浅睡时长，未采集字段显示「—」',
                          compact: true,
                        ),
                ),
                SectionCard(
                  title: '睡眠记录',
                  trailing: Text(
                    '共 $_total 条',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.bedtime_outlined,
                          title: '暂无睡眠记录',
                          description: '后端暂无睡眠数据，可在网页端添加',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final SleepRecord record in _items)
                              _SleepRow(record: record),
                          ],
                        ),
                ),
                if (_items.isNotEmpty)
                  ListLoadMoreFooter(
                    loading: _loadingMore,
                    hasMore: _hasMore,
                    onPressed: _loadMore,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 分阶段均值行：标签 + 数值（null 显示「—」）。
class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.minutes});

  final String label;
  final double? minutes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 12,
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          formatDuration(minutes?.round()),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 睡眠记录行：日期 + 时长/质量 + 入睡/起床 + 分阶段与醒来次数。
class _SleepRow extends StatelessWidget {
  const _SleepRow({required this.record});

  final SleepRecord record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String wakeLabel =
        record.wakeCount == null ? '—' : '${record.wakeCount} 次';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(record.recordDate, style: theme.textTheme.bodyMedium),
                Text(
                  '入睡 ${record.bedtime ?? '—'} · 起床 ${record.wakeTime ?? '—'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: <Widget>[
                    Text(
                      '深睡 ${formatDuration(record.deepSleepMin)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    Text(
                      '浅睡 ${formatDuration(record.lightSleepMin)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    Text(
                      '醒来 $wakeLabel',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
                if (record.note != null && record.note!.isNotEmpty)
                  Text(
                    record.note!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: <Widget>[
              Text(
                formatDuration(record.durationMin),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                record.sleepQuality == null
                    ? '质量 —'
                    : '质量 ${record.sleepQuality}/10',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
