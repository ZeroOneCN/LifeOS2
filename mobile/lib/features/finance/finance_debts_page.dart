import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import 'finance_status_widgets.dart';

/// 债务管理：汇总（借入/借出/未还）+ 全部债务分页。
///
/// 数据：`GET /finance/debts/stats?days=0`、`GET /finance/debts?page=&page_size=20`。
class FinanceDebtsPage extends StatefulWidget {
  const FinanceDebtsPage({super.key});

  @override
  State<FinanceDebtsPage> createState() => _FinanceDebtsPageState();
}

class _FinanceDebtsPageState extends State<FinanceDebtsPage> {
  final List<DebtItem> _items = <DebtItem>[];

  DebtStats? _stats;
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

  /// 首屏/重试：并行拉汇总与第一页，任一失败整体进入失败态。
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
            '/finance/debts/stats',
            queryParameters: <String, dynamic>{'days': 0},
          )
          .then((value) => value.data);
      final Future<Map<String, dynamic>?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/debts',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
          )
          .then((value) => value.data);
      final List<Map<String, dynamic>?> responses = await Future.wait(
        <Future<Map<String, dynamic>?>>[statsFuture, listFuture],
      );
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '债务接口返回数据为空',
        );
      }
      final List<DebtItem> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = DebtStats.fromJson(statsJson);
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

  /// 加载更多：追加下一页；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/finance/debts',
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

  /// 从分页响应中取出 `items` 并转为 [DebtItem]。
  List<DebtItem> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => DebtItem.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 列表页错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline =
        scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  /// 新增债务：保存成功返回 true 后重拉汇总与第一页。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/finance/debts/new');
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 打开债务详情；无论是否在详情里编辑/还款，返回后都重拉一次。
  Future<void> _openDetail(DebtItem item) async {
    await context.push<void>('/finance/debts/${item.id}', extra: item);
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DebtStats? stats = _stats;

    return DetailPageScaffold(
      title: '债务管理',
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
                    '共 ${stats.total} 笔',
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
                              label: '借入合计',
                              value: formatMoney(stats.borrowTotal),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '借出合计',
                              value: formatMoney(stats.lendTotal),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '未还余额',
                              value: formatMoney(stats.outstanding),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          StatusChip(
                            label: '进行中 ${stats.active}',
                            tone: StatusTone.info,
                          ),
                          StatusChip(
                            label: '已结清 ${stats.settled}',
                            tone: StatusTone.success,
                          ),
                          if (stats.overdue > 0)
                            StatusChip(
                              label: '逾期 ${stats.overdue}',
                              tone: StatusTone.danger,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '全部债务',
                  trailing: AppPrimaryAction(
                    label: '新增债务',
                    onPressed: _openCreate,
                  ),
                  child: Column(
                    spacing: 4,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_total > 0)
                        Text(
                          '共 $_total 条 · 按日期倒序',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_items.isEmpty)
                        const EmptyState(
                          icon: Icons.handshake_outlined,
                          title: '暂无债务记录',
                          description: '点右上角「新增债务」录入第一笔借入 / 借出',
                          compact: true,
                        )
                      else
                        // 整行只做一件事：进详情。还款入口统一放在详情页，
                        // 避免行尾小图标与整行点击互相抢手势。
                        for (final DebtItem item in _items)
                          _DebtRow(
                            item: item,
                            onTap: () => _openDetail(item),
                          ),
                    ],
                  ),
                ),
                if (_items.isNotEmpty)
                  _DebtsFooter(
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

/// 债务列表行：名称/方向 + 对方与日期 + 未还金额与状态。
class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.item, required this.onTap});

  final DebtItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: <Widget>[
            Row(
              spacing: 12,
              children: <Widget>[
                Expanded(
                  child: Row(
                    spacing: 6,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          item.name,
                          style: theme.textTheme.bodyMedium,
                          // 名称过长（如「存在我这里的钱」）时允许两行，
                          // 不再截成「存在我…」丢掉关键信息。
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StatusChip(
                        label: debtDirectionLabel(item.direction),
                        tone: item.isLend
                            ? StatusTone.info
                            : StatusTone.warning,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 2,
                  children: <Widget>[
                    Text(
                      formatMoney(item.outstanding),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    Text(
                      debtStatusLabel(item.status),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ],
            ),
            // 对方/日期/渠道独占整行：与金额同一行时 1.3x 下会把
            // 「支付宝」拆到第二行只剩一个「宝」，独占整行后完整可读。
            Text(
              <String>[
                if (item.counterparty != null && item.counterparty!.isNotEmpty)
                  item.counterparty!,
                item.debtDate,
                if (item.channel != null && item.channel!.isNotEmpty)
                  item.channel!,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 「加载更多 / 已全部加载」页脚。
class _DebtsFooter extends StatelessWidget {
  const _DebtsFooter({
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
