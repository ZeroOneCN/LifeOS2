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
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 健身运动：区间汇总 + 按类型汇总 + 按日期倒序的运动记录。
///
/// 数据：
/// - `GET /health/fitness/stats?days=`（7/30/0，0 表示全部）
/// - `GET /health/fitness?page=&page_size=20`（后端按 record_date 倒序）
/// - 增改删：`POST/PUT/DELETE /health/fitness`（编辑页左保存右删除）
///
/// 列表与统计使用同一个区间（近 N 天含当天），增改删后一起重拉，
/// 保证总时长 / 总消耗 / 次数与列表范围一致。
/// 消耗热量或距离为 null 时显示「—」，不按 0 展示。
class HealthFitnessPage extends StatefulWidget {
  const HealthFitnessPage({super.key});

  @override
  State<HealthFitnessPage> createState() => _HealthFitnessPageState();
}

class _HealthFitnessPageState extends State<HealthFitnessPage> {
  final List<FitnessRecord> _items = <FitnessRecord>[];

  int _days = 0;
  FitnessStats? _stats;
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

  /// 区间筛选起始日（`days<=0` 返回 null，表示全部）；列表与统计保持同一范围。
  String? get _startParam {
    if (_days <= 0) {
      return null;
    }
    final DateTime start = DateTime.now().subtract(Duration(days: _days - 1));
    return '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
  }

  /// 首屏/重试：并行拉当前区间统计与第一页记录，任一失败整体失败。
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
      final String? start = _startParam;
      final Map<String, dynamic> listQuery = <String, dynamic>{
        'page': 1,
        'page_size': 20,
        'start': ?start,
      };
      final List<Map<String, dynamic>?> responses = await Future.wait(
        <Future<Map<String, dynamic>?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/fitness/stats',
                queryParameters: <String, dynamic>{'days': _days},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/fitness',
                queryParameters: listQuery,
              )
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '运动接口返回数据为空',
        );
      }
      final List<FitnessRecord> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = FitnessStats.fromJson(statsJson);
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
      final bool offline =
          scope.auth.hasLocalSession &&
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

  /// 加载更多运动记录；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final String? start = _startParam;
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/fitness',
            queryParameters: <String, dynamic>{
              'page': _page + 1,
              'page_size': 20,
              'start': ?start,
            },
          )).data;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载更多失败：${error.message}')));
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 从分页响应中取出 `items` 并转为 [FitnessRecord]。
  List<FitnessRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => FitnessRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 切换统计区间（7 天 / 30 天 / 全部）；重新拉统计与第一页记录。
  void _changeRange(int days) {
    if (days == _days) {
      return;
    }
    setState(() => _days = days);
    _refresh();
  }

  /// 打开新增页；保存成功返回 true 后重拉统计与列表第一页。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/health/fitness/new');
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 打开编辑页；保存或删除后返回 true，回到列表立即重算汇总。
  Future<void> _openEdit(FitnessRecord record) async {
    final bool? changed = await context.push<bool>(
      '/health/fitness/edit/${record.id}',
      extra: record,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final FitnessStats? stats = _stats;

    return DetailPageScaffold(
      title: '健身运动',
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
              SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 7, label: Text('7 天')),
                  ButtonSegment<int>(value: 30, label: Text('30 天')),
                  ButtonSegment<int>(value: 0, label: Text('全部')),
                ],
                selected: <int>{_days},
                showSelectedIcon: false,
                onSelectionChanged: (Set<int> selection) =>
                    _changeRange(selection.first),
              ),
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '区间汇总',
                  trailing: Text(
                    _rangeLabel(_days),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: Row(
                    spacing: 16,
                    children: <Widget>[
                      Expanded(
                        child: MetricPlaceholder(
                          label: '总时长',
                          value: formatDuration(stats.totalMinutes),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '总消耗（kcal）',
                          value: _number(stats.totalCalories),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '记录条数',
                          value: formatInt(stats.totalCount),
                        ),
                      ),
                    ],
                  ),
                ),
                if (stats.byType.isNotEmpty)
                  SectionCard(
                    title: '按类型汇总',
                    child: Column(
                      spacing: 8,
                      children: <Widget>[
                        for (final FitnessTypeSummary item in stats.byType)
                          _TypeRow(item: item),
                      ],
                    ),
                  ),
                SectionCard(
                  title: '运动记录',
                  trailing: AppPrimaryAction(
                    label: '新增记录',
                    onPressed: _openCreate,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: <Widget>[
                      if (_total > 0)
                        Text(
                          '共 $_total 条 · 按日期倒序',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      if (_items.isEmpty)
                        const EmptyState(
                          icon: Icons.fitness_center_outlined,
                          title: '暂无运动记录',
                          description: '该区间暂无记录，点右上角「新增记录」添加',
                          compact: true,
                        )
                      else
                        for (int i = 0; i < _items.length; i++) ...<Widget>[
                          if (i == 0 ||
                              _items[i].recordDate != _items[i - 1].recordDate)
                            _DateHeader(date: _items[i].recordDate),
                          _FitnessRow(
                            record: _items[i],
                            onTap: () => _openEdit(_items[i]),
                          ),
                        ],
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

/// 统计区间文案。
String _rangeLabel(int days) {
  if (days <= 0) {
    return '全部记录';
  }
  return '近 $days 天';
}

/// 数值展示：整数不带小数，非整数保留一位；null 显示「—」。
String _number(num? value) {
  if (value == null) {
    return '—';
  }
  return value == value.roundToDouble()
      ? formatInt(value.round())
      : formatOneDecimal(value);
}

/// 按类型汇总行：类型 + 总时长 + 次数/消耗。
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.item});

  final FitnessTypeSummary item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: <Widget>[
        Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Text(
                fitnessTypeLabel(item.exerciseType),
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              formatDuration(item.minutes),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Text(
          '${item.count} 次 · ${_number(item.calories)} kcal',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// 日期分组标题：列表按日期倒序，同一天只在首条前出现一次。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        date,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 运动记录行：类型 + 时长 + 消耗 / 距离；点按进入编辑页。
///
/// 热量或距离缺失时显示「—」，不把空值渲染成 0 kcal / 0.00 km。
class _FitnessRow extends StatelessWidget {
  const _FitnessRow({required this.record, required this.onTap});

  final FitnessRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String calories = record.calories == null
        ? '消耗 —'
        : '消耗 ${_number(record.calories)} kcal';
    final String detail = record.distanceKm == null
        ? calories
        : '$calories · ${record.distanceKm!.toStringAsFixed(2)} km';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: <Widget>[
            Row(
              spacing: 8,
              children: <Widget>[
                Expanded(
                  child: Text(
                    fitnessTypeLabel(record.exerciseType),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatDuration(record.durationMin),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: muted),
              ],
            ),
            // 备注是自由文本，不作为结构化字段重复展示；编辑页仍可查看修改。
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
