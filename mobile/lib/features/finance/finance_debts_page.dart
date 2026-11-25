import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

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
    final AppTokens tokens = AppTokens.of(context);
    final DebtStats? stats = _stats;

    return DetailPageScaffold(
      title: '债务管理',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          if (stats != null) ...<Widget>[
            SummaryStrip(
              caption: '共 ${formatInt(stats.total)} 笔 · '
                  '进行中 ${formatInt(stats.active)} · '
                  '已结清 ${formatInt(stats.settled)}'
                  '${stats.overdue > 0 ? ' · 逾期 ${formatInt(stats.overdue)} 笔' : ''}',
              items: <StatRailItem>[
                StatRailItem(
                  label: '借入合计',
                  value: formatInt(stats.borrowTotal),
                  unit: '元',
                ),
                StatRailItem(
                  label: '借出合计',
                  value: formatInt(stats.lendTotal),
                  unit: '元',
                ),
                StatRailItem(
                  label: '未还余额',
                  value: formatInt(stats.outstanding),
                  unit: '元',
                  color: tokens.red,
                ),
              ],
            ),
            SectionHeader(
              title: '全部债务 · 共 ${formatInt(_total)} 笔',
              actionLabel: '新增债务',
              onAction: _openCreate,
            ),
            GroupCard(
              children: _items.isEmpty
                  ? const <Widget>[
                      EmptyState(
                        icon: Icons.handshake_outlined,
                        title: '暂无债务记录',
                        description: '点「新增债务」录入第一笔借入 / 借出',
                        compact: true,
                      ),
                    ]
                  : <Widget>[
                      // 整行只做一件事：进详情。还款入口统一放在详情页，
                      // 避免行尾小图标与整行点击互相抢手势。
                      for (final DebtItem item in _items)
                        _DebtRow(item: item, onTap: () => _openDetail(item)),
                    ],
            ),
          ],
        ],
        footer: _items.isNotEmpty
            ? ListLoadMoreFooter(
                loading: _loadingMore,
                hasMore: _hasMore,
                onPressed: _loadMore,
              )
            : null,
      ),
    );
  }
}

/// 债务列表行：名称与方向 + 对方/日期/渠道 → 未还金额与状态。
class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.item, required this.onTap});

  final DebtItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String meta = <String>[
      debtDirectionLabel(item.direction),
      if (item.counterparty != null && item.counterparty!.isNotEmpty)
        item.counterparty!,
      formatListDate(item.debtDate),
      if (item.channel != null && item.channel!.isNotEmpty) item.channel!,
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
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatMoney(item.outstanding),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(
                      color: item.status == 'settled'
                          ? tokens.text2
                          : tokens.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    debtStatusLabel(item.status),
                    maxLines: 1,
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
