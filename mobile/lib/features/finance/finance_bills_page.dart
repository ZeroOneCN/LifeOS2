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

/// 账单管理：汇总（待还/已还/利息）+ 即将到期 + 全部账单分页。
///
/// 数据：
/// - `GET /finance/loan-bills/stats?days=0`（全部口径的汇总与即将到期）
/// - `GET /finance/loan-bills?page=&page_size=20`（分页列表）
/// - `GET /finance/loan-platforms?page_size=100`（平台 id → 名称）
class FinanceBillsPage extends StatefulWidget {
  const FinanceBillsPage({super.key});

  @override
  State<FinanceBillsPage> createState() => _FinanceBillsPageState();
}

class _FinanceBillsPageState extends State<FinanceBillsPage> {
  final List<BillItem> _items = <BillItem>[];
  final Map<int, String> _platforms = <int, String>{};

  BillStats? _stats;
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

  /// 首屏/重试：并行拉汇总、第一页列表与平台名，任一失败整体进入失败态。
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
      final Future<Map<String, dynamic>?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-bills/stats',
            queryParameters: <String, dynamic>{'days': 0},
          )
          .then((value) => value.data);
      final Future<Map<String, dynamic>?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-bills',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
          )
          .then((value) => value.data);
      final Future<Map<String, dynamic>?> platformFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-platforms',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data);
      final List<Map<String, dynamic>?> responses =
          await Future.wait(<Future<Map<String, dynamic>?>>[
        statsFuture,
        listFuture,
        platformFuture,
      ]);
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      final Map<String, dynamic>? platformJson = responses[2];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '账单接口返回数据为空',
        );
      }
      final List<BillItem> items = _parseItems(listJson);
      final Map<int, String> platforms = <int, String>{};
      for (final Map item
          in ((platformJson?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()) {
        platforms[(item['id'] as num?)?.toInt() ?? -1] =
            item['name'] as String? ?? '';
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = BillStats.fromJson(statsJson);
        _items
          ..clear()
          ..addAll(items);
        _platforms
          ..clear()
          ..addAll(platforms);
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

  /// 加载更多：追加下一页；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/loan-bills',
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

  /// 从分页响应中取出 `items` 并转为 [BillItem]。
  List<BillItem> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => BillItem.fromJson(item.cast<String, dynamic>()))
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
    final BillStats? stats = _stats;

    return DetailPageScaffold(
      title: '账单管理',
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
                    '全部账单',
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
                              label: '待还',
                              value: formatMoney(stats.remaining),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '已还',
                              value: formatMoney(stats.paid),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '利息合计',
                              value: formatMoney(stats.totalInterest),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          StatusChip(
                            label: '待还 ${stats.pendingCount}',
                            tone: StatusTone.danger,
                          ),
                          StatusChip(
                            label: '部分还款 ${stats.partialCount}',
                            tone: StatusTone.warning,
                          ),
                          StatusChip(
                            label: '已结清 ${stats.clearedCount}',
                            tone: StatusTone.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (stats.upcoming.isNotEmpty)
                  SectionCard(
                    title: '即将到期',
                    child: Column(
                      spacing: 4,
                      children: <Widget>[
                        for (final BillItem bill in stats.upcoming)
                          BillRow(
                            bill: bill,
                            platformName: _platformName(bill.platformId),
                            onTap: () => _openDetail(bill),
                          ),
                      ],
                    ),
                  ),
                SectionCard(
                  title: '全部账单',
                  trailing: Text(
                    '共 $_total 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: '暂无账单',
                          description: '后端暂无账单数据',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final BillItem bill in _items)
                              BillRow(
                                bill: bill,
                                platformName: _platformName(bill.platformId),
                                onTap: () => _openDetail(bill),
                              ),
                          ],
                        ),
                ),
                if (_items.isNotEmpty)
                  _LoadMoreFooter(
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

  /// 平台 id → 名称；未拉到平台列表时退化为「平台 id」。
  String _platformName(int id) {
    final String? name = _platforms[id];
    if (name == null || name.isEmpty) {
      return '平台 $id';
    }
    return name;
  }

  /// 进入账单明细，平台名通过查询参数透传，省一次请求。
  void _openDetail(BillItem bill) {
    context.push(
      '/finance/bills/${bill.id}?platform=${Uri.encodeComponent(_platformName(bill.platformId))}',
    );
  }
}

/// 「加载更多 / 已全部加载」页脚。
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.hasMore,
    required this.onPressed,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '已加载全部',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return TextButton(onPressed: onPressed, child: const Text('加载更多'));
  }
}
