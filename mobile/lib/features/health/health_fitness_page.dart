import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_tokens.dart';

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

  /// 当前栏目：0 = 汇总，1 = 记录。
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
    final FitnessStats? stats = _stats;
    final bool ready =
        _status == LoadStatus.ready || _status == LoadStatus.idle;

    return DetailPageScaffold(
      title: '健身运动',
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
              caption: '${_rangeLabel(_days)} · '
                  '共 ${formatInt(stats.totalCount)} 条记录 · '
                  '${formatInt(stats.byType.length)} 种运动',
              items: <StatRailItem>[
                StatRailItem(
                  label: '总时长',
                  value: _durationCompact(stats.totalMinutes),
                ),
                StatRailItem(
                  label: '总消耗',
                  value: formatInt(stats.totalCalories),
                  unit: '千卡',
                ),
                StatRailItem(
                  label: '记录',
                  value: formatInt(stats.totalCount),
                  unit: '条',
                ),
              ],
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '7 天', value: 7),
                V2SegmentedOption<int>(label: '30 天', value: 30),
                V2SegmentedOption<int>(label: '全部', value: 0),
              ],
              selected: _days,
              onChanged: _changeRange,
              compact: true,
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '汇总', value: 0),
                V2SegmentedOption<int>(label: '记录', value: 1),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _summaryTab(stats),
                  _recordsTab(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 汇总栏目：按运动类型拆分时长、次数与消耗。
  Widget _summaryTab(FitnessStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '按类型汇总 · ${formatInt(stats.byType.length)} 类',
          actionLabel: '新增记录',
          onAction: _openCreate,
        ),
        GroupCard(
          children: stats.byType.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.fitness_center_outlined,
                    title: '该区间暂无运动汇总',
                    description: '点「新增记录」添加一条运动记录',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final FitnessTypeSummary item in stats.byType)
                    RecordRow(
                      title: fitnessTypeLabel(item.exerciseType),
                      subtitle:
                          '${formatInt(item.count)} 次 · ${formatInt(item.calories)} 千卡',
                      value: _durationCompact(item.minutes),
                    ),
                ],
        ),
        Text(
          '${_rangeLabel(_days)}的时长与消耗由运动记录汇总；缺失值显示「—」。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 记录栏目：按日期倒序分页展示运动明细。
  Widget _recordsTab() {
    final AppTokens tokens = AppTokens.of(context);
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '运动记录 · 共 ${formatInt(_total)} 条',
          actionLabel: '新增记录',
          onAction: _openCreate,
        ),
        GroupCard(
          children: _items.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.fitness_center_outlined,
                    title: '暂无运动记录',
                    description: '该区间暂无记录，点「新增记录」添加',
                    compact: true,
                  ),
                ]
              : <Widget>[
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
        Text(
          '共 ${formatInt(_total)} 条 · 按日期倒序；消耗热量或距离缺失时显示「—」。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
      footer: _items.isNotEmpty
          ? ListLoadMoreFooter(
              loading: _loadingMore,
              hasMore: _hasMore,
              onPressed: _loadMore,
            )
          : null,
    );
  }
}

/// 统计区间文案。
String _rangeLabel(int days) {
  if (days <= 0) {
    return '全部区间';
  }
  return '近 $days 天';
}

/// 日期分组标题：列表按日期倒序，同一天只在首条前出现一次。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(date, style: AppType.section.copyWith(color: tokens.text2)),
    );
  }
}

/// 时长压缩展示：`92` → `1h32m`；空值显示「—」。
String _durationCompact(int? minutes) {
  if (minutes == null || minutes <= 0) {
    return '—';
  }
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  if (hours == 0) {
    return '${rest}m';
  }
  return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
}

/// 运动记录行：类型 + 时长 + 消耗 / 距离；点按进入编辑页。
///
/// 热量或距离缺失时显示「—」，不把空值渲染成 0 千卡 / 0.00 km。
class _FitnessRow extends StatelessWidget {
  const _FitnessRow({required this.record, required this.onTap});

  final FitnessRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String detail = <String>[
      record.calories == null
          ? '消耗 —'
          : '消耗 ${formatInt(record.calories)} 千卡',
      if (record.distanceKm != null)
        '距离 ${record.distanceKm!.toStringAsFixed(2)} km',
    ].join(' · ');
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
                      fitnessTypeLabel(record.exerciseType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 2),
                    // 备注是自由文本，不作为结构化字段重复展示；编辑页仍可查看修改。
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _durationCompact(record.durationMin),
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
