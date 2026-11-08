import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import 'finance_status_widgets.dart';

/// 旅行开支：汇总（实付 / 原价 / 优惠）+ 按行程筛选 + 按分类支出 + 明细分页。
///
/// 数据（与网页端 `pages/finance/travel.tsx` 调用一致）：
/// - `GET /finance/travel/ledgers?page_size=100`
/// - `GET /finance/travel/details?page=&page_size=20[&ledger_id=]`
/// - `GET /finance/travel/details/stats?days=3650[&ledger_id=]`
class FinanceTravelPage extends StatefulWidget {
  const FinanceTravelPage({super.key});

  @override
  State<FinanceTravelPage> createState() => _FinanceTravelPageState();
}

class _FinanceTravelPageState extends State<FinanceTravelPage> {
  final List<TravelDetail> _items = <TravelDetail>[];
  final List<TravelLedger> _ledgers = <TravelLedger>[];

  TravelStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 0 表示「全部行程」；>0 时作为 `ledger_id` 传给后端。
  int _ledgerId = 0;

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

  /// 首屏 / 重试 / 切换行程：并行拉汇总、第一页明细与行程字典。
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
      final Map<String, dynamic> ledgerQuery = <String, dynamic>{
        if (_ledgerId > 0) 'ledger_id': _ledgerId,
      };
      final Future<Object?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/travel/details/stats',
            queryParameters: <String, dynamic>{
              'days': 3650,
              ...ledgerQuery,
            },
          )
          .then((value) => value.data);
      final Future<Object?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/travel/details',
            queryParameters: <String, dynamic>{
              'page': 1,
              'page_size': 20,
              ...ledgerQuery,
            },
          )
          .then((value) => value.data);
      final Future<Object?> ledgerFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/travel/ledgers',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data);
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[statsFuture, listFuture, ledgerFuture],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '旅行开支接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = TravelStats.fromJson(statsJson);
        _ledgers
          ..clear()
          ..addAll(_parseLedgers(responses[2]));
        _items
          ..clear()
          ..addAll(_parseItems(listJson));
        _page = 1;
        _total = (listJson['total'] as num?)?.toInt() ?? _items.length;
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

  /// 加载更多：沿用当前行程筛选条件。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/travel/details',
                  queryParameters: <String, dynamic>{
            'page': _page + 1,
            'page_size': 20,
            if (_ledgerId > 0) 'ledger_id': _ledgerId,
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

  /// 新增旅行开支：保存成功返回 true 后重拉汇总与列表。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/finance/travel/new');
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 编辑明细：带快照进入表单，保存后重拉汇总与列表。
  Future<void> _openEdit(TravelDetail detail) async {
    final bool? changed = await context.push<bool>(
      '/finance/travel/${detail.id}',
      extra: detail,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 删除明细：二次确认写明对合计与分类统计的影响。
  Future<void> _deleteDetail(TravelDetail detail) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除这条旅行开支？'),
          content: Text(
            '将删除「${detail.item}」（实付 ${formatMoney(detail.actualPrice)}）。\n'
            '删除后实付 / 原价 / 优惠合计与分类统计会同步回退，且无法恢复。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              second: AppDangerButton(
                label: '删除',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await scope.apiClient.delete<dynamic>(
        '/finance/travel/details/${detail.id}',
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条旅行开支')));
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('删除失败：${error.message}')));
    }
  }

  /// 打开行程 / 支付方式维护页；返回后重拉字典与列表。
  Future<void> _openManage() async {
    await context.push<Object?>('/finance/travel/manage');
    if (mounted) {
      await _refresh();
    }
  }

  /// 分页响应 `items` → [TravelDetail]。
  List<TravelDetail> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => TravelDetail.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 行程字典（其实也是分页响应）→ [TravelLedger]。
  List<TravelLedger> _parseLedgers(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const <TravelLedger>[];
    }
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => TravelLedger.fromJson(item.cast<String, dynamic>()))
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
    final TravelStats? stats = _stats;
    // 后端会返回金额为 0 的分类，展示层过滤掉，避免「¥0.00」噪音。
    final List<NameAmount> categories = stats == null
        ? const <NameAmount>[]
        : stats.byCategory
            .where((NameAmount entry) => entry.amount > 0)
            .toList(growable: false);

    return DetailPageScaffold(
      title: '旅行开支',
      actions: <Widget>[
        IconButton(
          tooltip: '维护行程与支付方式',
          onPressed: _openManage,
          icon: const Icon(Icons.tune_outlined),
        ),
        IconButton(
          tooltip: '新增旅行开支',
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
              if (_ledgers.isNotEmpty)
                SectionCard(
                  title: '行程筛选',
                  child: AppSelectField<int>(
                    label: '行程',
                    value: _ledgerId,
                    options: <AppSelectOption<int>>[
                      const AppSelectOption<int>(value: 0, label: '全部行程'),
                      for (final TravelLedger ledger in _ledgers)
                        AppSelectOption<int>(
                          value: ledger.id,
                          label: ledger.name,
                        ),
                    ],
                    onChanged: (int value) {
                      if (value == _ledgerId) {
                        return;
                      }
                      setState(() => _ledgerId = value);
                      _refresh();
                    },
                  ),
                ),
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '合计',
                  trailing: Text(
                    '共 ${formatInt(stats.count)} 笔',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Row(
                    spacing: 16,
                    children: <Widget>[
                      Expanded(
                        child: MetricPlaceholder(
                          label: '实付合计',
                          value: formatMoney(stats.totalActual),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '原价合计',
                          value: formatMoney(stats.totalOriginal),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '优惠合计',
                          value: formatMoney(stats.totalDiscount),
                          // 优惠是「省下来的钱」，用语义成功色区分实付 / 原价。
                          valueColor: context.semanticColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
                if (categories.isNotEmpty)
                  SectionCard(
                    title: '按分类支出',
                    child: AmountBreakdownList(entries: categories),
                  ),
                SectionCard(
                  title: '开支明细',
                  trailing: Text(
                    '共 $_total 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.train_outlined,
                          title: '该行程暂无开支',
                          description: '切换其他行程，或先在网页端录入消费明细',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final TravelDetail detail in _items)
                              _TravelRow(
                                detail: detail,
                                ledgerName: _ledgerName(detail.ledgerId),
                                onEdit: () => _openEdit(detail),
                                onDelete: () => _deleteDetail(detail),
                              ),
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

  /// 行程 id → 名称；未知时返回 null（不展示）。
  String? _ledgerName(int? id) {
    if (id == null) {
      return null;
    }
    for (final TravelLedger ledger in _ledgers) {
      if (ledger.id == id) {
        return ledger.name;
      }
    }
    return null;
  }
}

/// 单条旅行明细：项目 + 日期/分类/时长/行程 + 实付与优惠。
class _TravelRow extends StatelessWidget {
  const _TravelRow({
    required this.detail,
    this.ledgerName,
    required this.onEdit,
    required this.onDelete,
  });

  final TravelDetail detail;
  final String? ledgerName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: muted);
    final List<Widget> meta = <Widget>[
      // 明细里有消费日与行程（名称本身带出发日期）两个日期，加前缀区分。
      // 消费日与账单 / 购物 / 流水列表统一成同年 `MM-dd`。
      Text('消费 ${formatListDate(detail.detailDate)}', style: metaStyle),
      Text(detail.category, style: metaStyle),
      if (detail.durationMinutes != null)
        Text(detail.durationText, style: metaStyle),
      if (ledgerName != null) Text('行程 $ledgerName', style: metaStyle),
    ];
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: <Widget>[
                  Text(
                    detail.item,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  // 元信息用 Wrap：窄屏 / 1.3x 字体下换行而不是省略号截断。
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: meta,
                  ),
                  if (detail.discount > 0)
                    // 优惠用成功色：与汇总卡「优惠合计」同色，扫视时能一眼分开
                    // 实付（正文色）与省下的金额。
                    Text.rich(
                      TextSpan(
                        style: metaStyle,
                        children: <TextSpan>[
                          TextSpan(
                            text: '原价 ${formatMoney(detail.originalPrice)} · ',
                          ),
                          TextSpan(
                            text: '优惠 ${formatMoney(detail.discount)}',
                            style: TextStyle(
                              color: context.semanticColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              formatMoney(detail.actualPrice),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              padding: EdgeInsets.zero,
              onSelected: (String value) {
                if (value == 'edit') {
                  onEdit();
                } else {
                  onDelete();
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                PopupMenuItem<String>(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
