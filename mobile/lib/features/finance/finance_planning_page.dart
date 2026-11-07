import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import 'finance_status_widgets.dart';

/// 财务规划：汇总（目标 / 已存 / 完成率、进行中 / 已完成）+ 按类型已存 + 规划分页。
///
/// 数据（与网页端 `pages/finance/planning.tsx` 调用一致）：
/// - `GET /finance/planning?page=&page_size=20`
/// - `GET /finance/planning/stats?days=0`（0 = 全部时间；30 天窗口会把历史规划算成 0）
class FinancePlanningPage extends StatefulWidget {
  const FinancePlanningPage({super.key});

  @override
  State<FinancePlanningPage> createState() => _FinancePlanningPageState();
}

class _FinancePlanningPageState extends State<FinancePlanningPage> {
  final List<PlanItem> _items = <PlanItem>[];

  PlanStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 首屏 / 重试：并行拉汇总与第一页规划。
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
      final Future<Object?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/planning/stats',
            queryParameters: <String, dynamic>{'days': 0},
          )
          .then((value) => value.data);
      final Future<Object?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/planning',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
          )
          .then((value) => value.data);
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[statsFuture, listFuture],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '财务规划接口返回数据为空',
        );
      }
      final List<PlanItem> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = PlanStats.fromJson(statsJson);
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
      setState(() {
        _status = _errorStatus(scope, error);
        _message = error.message;
      });
    }
  }

  /// 加载更多：追加下一页规划。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/planning',
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

  /// 新增规划：保存成功返回 true 后重拉汇总与列表。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/finance/planning/new');
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 分页响应 `items` → [PlanItem]。
  List<PlanItem> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => PlanItem.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 列表页错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PlanStats? stats = _stats;
    // 只展示有已存金额的类型；金额为 0 的类型在窄屏上只是噪音。
    final List<NameAmount> types = stats == null
        ? const <NameAmount>[]
        : <NameAmount>[
            for (final PlanTypeStat type in stats.byType)
              if (type.amount > 0)
                NameAmount(id: -1, name: type.planType, amount: type.amount),
          ];

    return DetailPageScaffold(
      title: '财务规划',
      actions: <Widget>[
        IconButton(
          tooltip: '新增规划',
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
        ),
      ],
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
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '合计',
                  trailing: Text(
                    '全部规划',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: MetricPlaceholder(
                              label: '目标合计',
                              value: formatMoney(stats.targetTotal),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '已存合计',
                              value: formatMoney(stats.savedTotal),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '整体完成率',
                              value: formatPercent(
                                stats.targetTotal <= 0
                                    ? null
                                    : stats.savedTotal /
                                        stats.targetTotal *
                                        100,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: MetricPlaceholder(
                              label: '规划总数',
                              value: formatInt(stats.total),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '进行中',
                              value: formatInt(stats.active),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '已完成',
                              value: formatInt(stats.done),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (types.isNotEmpty)
                  SectionCard(
                    title: '按类型已存',
                    trailing: Text(
                      '共 ${formatInt(types.length)} 类',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    child: AmountBreakdownList(entries: types),
                  ),
                SectionCard(
                  title: '全部规划',
                  trailing: Text(
                    '共 $_total 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.flag_outlined,
                          title: '暂无规划',
                          description: '可在网页端新增储蓄、消费或投资规划',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final PlanItem plan in _items)
                              _PlanRow(plan: plan),
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

/// 单条规划：标题 + 状态 + 日期/类型 + 已存与目标 + 进度条。
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan});

  final PlanItem plan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final double? progress = plan.progress;
    final String? target = plan.targetAmount == null
        ? null
        : formatMoney(plan.targetAmount);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: <Widget>[
              Expanded(
                child: Text(
                  plan.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              StatusChip(
                label: planStatusLabel(plan.status),
                tone: _planTone(plan.status),
              ),
            ],
          ),
          Text(
            <String>[
              plan.planDate,
              // 「目标」单独出现时会被读成缺值（目标是什么？），补「计划」
              // 明确它是规划类型。
              if (plan.planType.isNotEmpty) '${plan.planType}计划',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          Row(
            spacing: 12,
            children: <Widget>[
              Expanded(
                child: Text(
                  '已存 ${formatMoney(plan.savedAmount)}',
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              Text(
                target == null ? '未设目标' : '目标 $target',
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: <Widget>[
              Expanded(
                child: LinearProgressIndicator(
                  value: progress ?? 0,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // 进度条只有视觉长度，补一个具体百分比，便于精确对照。
              Text(
                formatPercent(progress == null ? null : progress * 100),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 规划状态 → 状态标签配色：完成绿、放弃橙、进行中蓝。
  StatusTone _planTone(String status) {
    switch (status) {
      case 'done':
        return StatusTone.success;
      case 'abandoned':
        return StatusTone.warning;
      default:
        return StatusTone.info;
    }
  }
}
