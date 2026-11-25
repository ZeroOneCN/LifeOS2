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

/// 饮食记录：今日摄入汇总 + 按日期倒序、同日按餐次排列的记录列表。
///
/// 数据：
/// - `GET /health/diet/stats?days=0`（全部区间，返回逐日 `trend`）
/// - `GET /health/diet?page=&page_size=20`（后端按 record_date 倒序）
/// - 增改删：`POST/PUT/DELETE /health/diet`（编辑页左保存右删除）
///
/// 口径一致性：顶部「今日摄入」与列表里的每日小计都取统计接口 `trend` 的
/// 同一条记录（`DietStats.forDate`），不分别按列表分页数据重算，
/// 因此同一天两处数字必然一致（列表分页只影响记录明细，不影响小计）。
/// 热量 / 三大营养素为 null 时显示「—」，不按 0 展示。
class HealthDietPage extends StatefulWidget {
  const HealthDietPage({super.key});

  @override
  State<HealthDietPage> createState() => _HealthDietPageState();
}

class _HealthDietPageState extends State<HealthDietPage> {
  final List<DietRecord> _items = <DietRecord>[];

  DietStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 当前栏目：0 = 今日，1 = 历史。
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

  /// 今日日期 `yyyy-MM-dd`（统计 trend 与记录 `record_date` 同口径）。
  static String get _todayText {
    final DateTime now = DateTime.now();
    return '${now.year}-${_two(now.month)}-${_two(now.day)}';
  }

  static String _two(int value) => value < 10 ? '0$value' : '$value';

  /// 首屏/重试：并行拉全部区间统计与第一页记录，任一失败整体失败。
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
      final List<Map<String, dynamic>?> responses = await Future.wait(
        <Future<Map<String, dynamic>?>>[
          scope.apiClient
              // days=0 表示全部区间：列表不按区间过滤，统计也取全量，
              // 才能保证列表里任意一天的每日小计都有对应数据。
              .get<Map<String, dynamic>>(
                '/health/diet/stats',
                queryParameters: <String, dynamic>{'days': 0},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/diet',
                queryParameters: <String, dynamic>{
                  'page': 1,
                  'page_size': 20,
                },
              )
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '饮食接口返回数据为空',
        );
      }
      final List<DietRecord> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = DietStats.fromJson(statsJson);
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

  /// 加载更多饮食记录；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/diet',
            queryParameters: <String, dynamic>{
              'page': _page + 1,
              'page_size': 20,
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

  /// 从分页响应中取出 `items` 并转为 [DietRecord]。
  List<DietRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => DietRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 列表顺序：日期倒序；同一天按 早餐 → 午餐 → 晚餐 → 加餐；同餐次按 id 升序。
  List<DietRecord> get _sortedItems {
    final List<DietRecord> items = List<DietRecord>.of(_items);
    items.sort((DietRecord a, DietRecord b) {
      final int byDate = b.recordDate.compareTo(a.recordDate);
      if (byDate != 0) {
        return byDate;
      }
      final int byMeal = mealTypeOrder(
        a.mealType,
      ).compareTo(mealTypeOrder(b.mealType));
      if (byMeal != 0) {
        return byMeal;
      }
      return a.id.compareTo(b.id);
    });
    return items;
  }

  /// 打开新增页；保存成功返回 true 后重拉统计与列表第一页。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/health/diet/new');
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 打开编辑页；保存或删除后返回 true，回到列表立即重算今日与每日小计。
  Future<void> _openEdit(DietRecord record) async {
    final bool? changed = await context.push<bool>(
      '/health/diet/edit/${record.id}',
      extra: record,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DietStats? stats = _stats;
    final DietDayTotals? today = stats?.forDate(_todayText);
    final bool ready =
        _status == LoadStatus.ready || _status == LoadStatus.idle;

    return DetailPageScaffold(
      title: '饮食记录',
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
              caption: '$_todayText · 今日 ${formatInt(today?.count ?? 0)} 条 · '
                  '全部 ${formatInt(_total)} 条',
              items: <StatRailItem>[
                StatRailItem(
                  label: '今日热量',
                  value: formatInt(today?.calories),
                  unit: today == null ? null : '千卡',
                ),
                StatRailItem(
                  label: '蛋白质',
                  value: formatOneDecimal(today?.protein),
                  unit: today == null ? null : 'g',
                ),
                StatRailItem(
                  label: '碳水',
                  value: formatOneDecimal(today?.carbs),
                  unit: today == null ? null : 'g',
                ),
                StatRailItem(
                  label: '脂肪',
                  value: formatOneDecimal(today?.fat),
                  unit: today == null ? null : 'g',
                ),
              ],
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '今日', value: 0),
                V2SegmentedOption<int>(label: '历史', value: 1),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _buildTab(todayOnly: true),
                  _buildTab(todayOnly: false),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建今日 / 历史栏目：各自独立滚动，共用同一份分页数据与状态。
  Widget _buildTab({required bool todayOnly}) {
    final AppTokens tokens = AppTokens.of(context);
    final List<DietRecord> items = todayOnly
        ? _sortedItems
              .where((DietRecord item) => item.recordDate == _todayText)
              .toList(growable: false)
        : _sortedItems;
    final int count = todayOnly
        ? (_stats?.forDate(_todayText)?.count ?? items.length)
        : _total;
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: todayOnly
              ? '今日记录 · 共 ${formatInt(count)} 条'
              : '历史记录 · 共 ${formatInt(count)} 条',
          actionLabel: '新增记录',
          onAction: _openCreate,
        ),
        GroupCard(
          children: items.isEmpty
              ? <Widget>[
                  EmptyState(
                    icon: Icons.restaurant_outlined,
                    title: todayOnly ? '今天还没有饮食记录' : '暂无饮食记录',
                    description: todayOnly
                        ? '点「新增记录」添加今天第一餐'
                        : '点「新增记录」添加第一条记录',
                    compact: true,
                  ),
                ]
              : (todayOnly
                  ? <Widget>[
                      for (final DietRecord item in items)
                        _DietRow(record: item, onTap: () => _openEdit(item)),
                    ]
                  : _buildGroups()),
        ),
        Text(
          todayOnly
              ? '今日摄入与每日小计同源；热量或营养素缺失时显示「—」。'
              : '按日期倒序，同日按餐次排列；每日小计与今日摄入同源。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
      // 分页只作用于「历史」；今日栏目没有更多今日记录可加载。
      footer: !todayOnly && _items.isNotEmpty
          ? ListLoadMoreFooter(
              loading: _loadingMore,
              hasMore: _hasMore,
              onPressed: _loadMore,
            )
          : null,
    );
  }

  /// 构建「日期标题（含当日小计）+ 该日记录行」，日期与餐次顺序由 [_sortedItems] 保证。
  List<Widget> _buildGroups() {
    final List<DietRecord> items = _sortedItems;
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final DietRecord item = items[i];
      if (i == 0 || item.recordDate != items[i - 1].recordDate) {
        children.add(
          _DateHeader(
            date: item.recordDate,
            totals: _stats?.forDate(item.recordDate),
            isToday: item.recordDate == _todayText,
          ),
        );
      }
      children.add(_DietRow(record: item, onTap: () => _openEdit(item)));
    }
    return children;
  }
}

/// 日期分组标题：日期（今天额外标注）+ 当日热量 + 三大营养素小计。
///
/// 小计取自统计接口 trend，与顶部「今日摄入」同源；当天统计缺失时只显示日期。
class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.date,
    required this.totals,
    required this.isToday,
  });

  final String date;
  final DietDayTotals? totals;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final DietDayTotals? day = totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: <Widget>[
          Row(
            spacing: 8,
            children: <Widget>[
              Expanded(
                child: Text(
                  isToday
                      ? '${formatListDate(date)} · 今天'
                      : formatListDate(date),
                  style: AppType.rowMeta.copyWith(
                    color: tokens.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (day != null)
                Text(
                  '${formatInt(day.calories)} 千卡',
                  maxLines: 1,
                  softWrap: false,
                  style: AppType.rowMeta.copyWith(
                    color: tokens.text3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (day != null)
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                _NutrientTag(label: '蛋白质', value: day.protein),
                _NutrientTag(label: '碳水', value: day.carbs),
                _NutrientTag(label: '脂肪', value: day.fat),
              ],
            ),
        ],
      ),
    );
  }
}

/// 小计里的单项营养素：`蛋白质 56.0 g`。
class _NutrientTag extends StatelessWidget {
  const _NutrientTag({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Text(
      '$label ${formatOneDecimal(value)} g',
      style: AppType.rowMeta.copyWith(color: tokens.text3),
    );
  }
}

/// 饮食记录行：食物名 + 餐次/克数 + 热量与三大营养素；点按进入编辑页。
///
/// 热量或营养素缺失时显示「—」，不把空值渲染成 0 千卡 / 0 g。
class _DietRow extends StatelessWidget {
  const _DietRow({required this.record, required this.onTap});

  final DietRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String meta = <String>[
      mealTypeLabel(record.mealType),
      '${formatCompact(record.weightG)} g',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 2,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          record.foodName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.rowTitle.copyWith(color: tokens.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.rowMeta.copyWith(
                            color: tokens.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${formatInt(record.calories)} 千卡',
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(
                      color: record.calories == null
                          ? tokens.text3
                          : tokens.text,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 15, color: tokens.text3),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: <Widget>[
                  Text(
                    '蛋白质 ${formatOneDecimal(record.protein)} g',
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                  Text(
                    '碳水 ${formatOneDecimal(record.carbs)} g',
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                  Text(
                    '脂肪 ${formatOneDecimal(record.fat)} g',
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ],
              ),
              if (record.note != null && record.note!.isNotEmpty)
                Text(
                  record.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowMeta.copyWith(color: tokens.text3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
