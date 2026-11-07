import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/queue/outbox_controller.dart';
import '../../core/queue/outbox_entry.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../finance/finance_status_widgets.dart';

/// 外汇交易：资金动态（四卡 + 明细）+ 交易记录（分页 + 净盈亏正负色）。
///
/// 数据（与网页端 `pages/investment/forex.tsx` 调用一致）：
/// - `GET /investment/funds/stats?start=&end=`：入金 / 出金 / 体验金 / 净投入 + 按日聚合；
/// - `GET /investment/funds?page=&page_size=20`：资金明细（接口不支持日期参数，区间内本地筛选）；
/// - `GET /investment/forex?page=&page_size=20&start=&end=`：交易记录。
///
/// 页内「统计区间」是唯一时间口径：资金四卡、三色柱图、资金明细与交易记录
/// 全部由同一个 `_rangeDays` 推导出的 `start` / `end` 拉取，避免两处区间不一致。
///
/// 新增 / 编辑交易分别进入 `/invest/forex/new`、`/invest/forex/edit/{id}`，
/// 返回 `true` 后刷新汇总与两个列表。
class ForexPage extends StatefulWidget {
  const ForexPage({super.key});

  @override
  State<ForexPage> createState() => _ForexPageState();
}

class _ForexPageState extends State<ForexPage> {
  static const int _pageSize = 20;

  final List<FundRecord> _funds = <FundRecord>[];
  final List<ForexTrade> _trades = <ForexTrade>[];

  FundStats? _fundStats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 统计区间天数：0 = 全部，30 / 90 为近 N 天（含今天）。
  int _rangeDays = 0;

  int _fundPage = 1;
  int _fundTotal = 0;
  bool _fundHasMore = false;
  bool _fundLoadingMore = false;

  int _tradePage = 1;
  int _tradeTotal = 0;
  bool _tradeHasMore = false;
  bool _tradeLoadingMore = false;

  OutboxController? _outbox;
  DateTime? _seenSyncAt;

  /// 区间左边界（`YYYY-MM-DD`）；全部时为空。
  String? get _rangeStart {
    if (_rangeDays == 0) {
      return null;
    }
    final DateTime today = DateTime.now();
    final DateTime start = today.subtract(Duration(days: _rangeDays - 1));
    return _dateKey(start);
  }

  /// 区间右边界（今天）；全部时为空。
  String? get _rangeEnd => _rangeDays == 0 ? null : _dateKey(DateTime.now());

  /// 区间参数：全部时不传，保证列表与统计都不带日期过滤。
  Map<String, dynamic> get _rangeParams => <String, dynamic>{
    if (_rangeStart != null) 'start': _rangeStart,
    if (_rangeEnd != null) 'end': _rangeEnd,
  };

  /// 区间文案：`全部` / `近 30 天`。
  String get _rangeLabel => _rangeDays == 0 ? '全部' : '近 $_rangeDays 天';

  /// `DateTime` → `YYYY-MM-DD`。
  String _dateKey(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final OutboxController outbox = AppScope.of(context).outbox;
    if (_outbox == outbox) {
      return;
    }
    _outbox?.removeListener(_onOutboxChanged);
    _outbox = outbox;
    _seenSyncAt = outbox.lastSyncAt;
    outbox.addListener(_onOutboxChanged);
  }

  @override
  void dispose() {
    _outbox?.removeListener(_onOutboxChanged);
    super.dispose();
  }

  /// 队列变化：刷新「待同步」临时行；推送成功后重新拉服务端真实记录，
  /// 让临时行消失、真实行补上，不会同时出现两条。
  void _onOutboxChanged() {
    if (!mounted) {
      return;
    }
    final DateTime? syncAt = _outbox?.lastSyncAt;
    final bool syncAdvanced = syncAt != null && syncAt != _seenSyncAt;
    if (syncAdvanced) {
      _seenSyncAt = syncAt;
    }
    setState(() {});
    if (syncAdvanced) {
      _refresh();
    }
  }

  /// 首屏/重试：并行拉资金合计、资金明细第一页、交易第一页。
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
      _status = _fundStats == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/funds/stats',
                queryParameters: _rangeParams,
              )
              .then((value) => value.data),
          _loadFunds(scope),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/forex',
                queryParameters: <String, dynamic>{
                  ..._rangeParams,
                  'page': 1,
                  'page_size': _pageSize,
                },
              )
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final ({List<FundRecord> items, int total, bool hasMore}) fundResult =
          responses[1] as ({List<FundRecord> items, int total, bool hasMore});
      final Map<String, dynamic>? tradeJson =
          responses[2] as Map<String, dynamic>?;
      if (statsJson == null || tradeJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '资金或交易接口返回数据为空',
        );
      }
      final List<ForexTrade> trades = _parseTrades(tradeJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _fundStats = FundStats.fromJson(statsJson);
        _funds
          ..clear()
          ..addAll(fundResult.items);
        _trades
          ..clear()
          ..addAll(trades);
        _fundPage = 1;
        _fundTotal = fundResult.total;
        _fundHasMore = fundResult.hasMore;
        _tradePage = 1;
        _tradeTotal = (tradeJson['total'] as num?)?.toInt() ?? trades.length;
        _tradeHasMore = _trades.length < _tradeTotal;
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

  /// 拉资金明细：与统计同一区间。
  ///
  /// 资金明细接口只支持 `page` / `page_size` / `record_type`，没有日期参数，
  /// 因此「全部」沿用服务端分页；选了区间时取满前 5 页（≤500 条）后本地按
  /// 发生日期筛选，保证明细与四卡、柱图口径一致。
  Future<({List<FundRecord> items, int total, bool hasMore})> _loadFunds(
    AppScope scope,
  ) async {
    if (_rangeDays == 0) {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/funds',
                queryParameters: <String, dynamic>{
                  'page': 1,
                  'page_size': _pageSize,
                },
              ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '资金明细接口返回数据为空',
        );
      }
      final List<FundRecord> items = _parseFunds(json);
      final int total = (json['total'] as num?)?.toInt() ?? items.length;
      return (items: items, total: total, hasMore: items.length < total);
    }
    final String start = _rangeStart!;
    final List<FundRecord> all = <FundRecord>[];
    int total = 0;
    for (int page = 1; page <= 5; page++) {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/funds',
                queryParameters: <String, dynamic>{
                  'page': page,
                  'page_size': 100,
                },
              ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '资金明细接口返回数据为空',
        );
      }
      final List<FundRecord> items = _parseFunds(json);
      total = (json['total'] as num?)?.toInt() ?? all.length;
      all.addAll(items);
      if (items.isEmpty || all.length >= total) {
        break;
      }
    }
    final List<FundRecord> filtered = all
        .where((FundRecord record) => record.recordDate.compareTo(start) >= 0)
        .toList();
    return (items: filtered, total: filtered.length, hasMore: false);
  }

  /// 切换统计区间：四卡、柱图、明细与交易记录使用同一组 `start` / `end` 重拉。
  void _setRange(int days) {
    if (days == _rangeDays) {
      return;
    }
    setState(() => _rangeDays = days);
    _refresh();
  }

  /// 资金明细「加载更多」：追加下一页；失败只提示，不清空已加载数据。
  Future<void> _loadMoreFunds() async {
    if (_fundLoadingMore || !_fundHasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _fundLoadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/investment/funds',
                  queryParameters: <String, dynamic>{
            'page': _fundPage + 1,
            'page_size': _pageSize,
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
        _fundPage += 1;
        _funds.addAll(_parseFunds(json));
        _fundTotal = (json['total'] as num?)?.toInt() ?? _funds.length;
        _fundHasMore = _funds.length < _fundTotal;
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
        setState(() => _fundLoadingMore = false);
      }
    }
  }

  /// 交易记录「加载更多」：追加下一页；失败只提示，不清空已加载数据。
  Future<void> _loadMoreTrades() async {
    if (_tradeLoadingMore || !_tradeHasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _tradeLoadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/investment/forex',
                  queryParameters: <String, dynamic>{
            ..._rangeParams,
            'page': _tradePage + 1,
            'page_size': _pageSize,
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
        _tradePage += 1;
        _trades.addAll(_parseTrades(json));
        _tradeTotal = (json['total'] as num?)?.toInt() ?? _trades.length;
        _tradeHasMore = _trades.length < _tradeTotal;
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
        setState(() => _tradeLoadingMore = false);
      }
    }
  }

  /// 进入新增页；保存成功（返回 true）后刷新汇总与两个列表。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/invest/forex/new');
    if (created != true || !mounted) {
      return;
    }
    final OutboxController outbox = AppScope.of(context).outbox;
    if (outbox.isOnline) {
      await _refresh();
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outbox.isOnline ? '交易已保存，正在同步到服务器' : '交易已存本地，联网后自动同步',
        ),
      ),
    );
  }

  /// 新增资金记录；保存成功后刷新汇总与资金明细。
  Future<void> _openFundCreate() async {
    final bool? changed = await context.push<bool>('/invest/forex/funds/new');
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 编辑 / 删除资金记录；返回 true 后刷新。
  Future<void> _openFundEdit(FundRecord record) async {
    final bool? changed = await context.push<bool>(
      '/invest/forex/funds/edit/${record.id}',
      extra: record,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 编辑 / 删除交易；返回 true 后重拉汇总与两个列表。
  Future<void> _openTradeEdit(ForexTrade trade) async {
    final bool? changed = await context.push<bool>(
      '/invest/forex/edit/${trade.id}',
      extra: trade,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 资金分页响应 `items` → [FundRecord]。
  List<FundRecord> _parseFunds(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => FundRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 交易分页响应 `items` → [ForexTrade]。
  List<ForexTrade> _parseTrades(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => ForexTrade.fromJson(item.cast<String, dynamic>()))
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
    final TextStyle? trailingStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final OutboxController outbox = AppScope.of(context).outbox;

    return ListenableBuilder(
      listenable: outbox,
      builder: (BuildContext context, Widget? _) {
        final List<OutboxEntry> pending =
            outbox.pendingOf(outboxOpForexCreate);
        return DetailPageScaffold(
          title: '外汇交易',
          // 主操作放底栏而非悬浮按钮：底栏独立占位，内容只在其上方滚动，
          // 柱图 X 轴末标签不会被按钮压住（1.3x 字号同样不遮挡）。
          bottomBar: AppPrimaryButton(
            label: '新增交易',
            onPressed: _openCreate,
          ),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: <Widget>[
                  if (pending.isNotEmpty) _PendingTradesCard(
                    entries: pending,
                    outbox: outbox,
                    theme: theme,
                  ),
                  ListStatusView(
                    status: _status,
                    message: _message,
                    onRetry: _refresh,
                  ),
                  if (_status == LoadStatus.ready) ...<Widget>[
                    SectionCard(
                      title: '资金动态',
                      trailing: AppPrimaryAction(
                        label: '记录资金',
                        onPressed: _openFundCreate,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: <Widget>[
                          // 时间范围紧贴标题下方：唯一的统计口径，
                          // 四卡、柱图、明细与交易记录都按它重拉。
                          SegmentedButton<int>(
                            segments: const <ButtonSegment<int>>[
                              ButtonSegment<int>(
                                value: 30,
                                label: Text('近 30 天', maxLines: 1),
                              ),
                              ButtonSegment<int>(
                                value: 90,
                                label: Text('近 90 天', maxLines: 1),
                              ),
                              ButtonSegment<int>(
                                value: 0,
                                label: Text('全部', maxLines: 1),
                              ),
                            ],
                            selected: <int>{_rangeDays},
                            showSelectedIcon: false,
                            onSelectionChanged: (Set<int> selection) =>
                                _setRange(selection.first),
                          ),
                          Text(
                            '$_rangeLabel · 四卡、柱图、明细与交易记录同口径',
                            style: trailingStyle,
                          ),
                          Text(
                            '共 $_fundTotal 笔 · 按发生日期倒序',
                            style: trailingStyle,
                          ),
                          _FundMetrics(stats: _fundStats),
                          _FundByDateChart(
                            days: _fundStats?.byDate ?? const <FundDayStat>[],
                          ),
                          if (_funds.isEmpty)
                            EmptyState(
                              icon: Icons.account_balance_wallet_outlined,
                              title: _rangeDays == 0 ? '暂无资金记录' : '该区间没有资金记录',
                              description: _rangeDays == 0
                                  ? '点右上角「记录资金」录入第一笔'
                                  : '可切换上方「全部」查看历史记录',
                              compact: true,
                            )
                          else
                            Column(
                              children: <Widget>[
                                for (final FundRecord record in _funds)
                                  _FundRow(
                                    record: record,
                                    onTap: () => _openFundEdit(record),
                                  ),
                              ],
                            ),
                          if (_funds.isNotEmpty)
                            ListLoadMoreFooter(
                              loading: _fundLoadingMore,
                              hasMore: _fundHasMore,
                              onPressed: _loadMoreFunds,
                            ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: '交易记录',
                      trailing: Text(
                        '$_rangeLabel · 共 $_tradeTotal 笔'
                        '${pending.isEmpty ? '' : ' · 待同步 ${pending.length}'}',
                        style: trailingStyle,
                      ),
                      child: _trades.isEmpty
                          ? EmptyState(
                              icon: Icons.show_chart_outlined,
                              title: _rangeDays == 0 ? '暂无交易记录' : '该区间没有交易记录',
                              description: _rangeDays == 0
                                  ? '点底部「新增交易」录入第一笔'
                                  : '可切换上方「全部」查看历史记录',
                              compact: true,
                            )
                          : Column(
                              children: <Widget>[
                                for (final ForexTrade trade in _trades)
                                  _TradeRow(
                                    trade: trade,
                                    onTap: () => _openTradeEdit(trade),
                                  ),
                              ],
                            ),
                    ),
                    if (_trades.isNotEmpty)
                      ListLoadMoreFooter(
                        loading: _tradeLoadingMore,
                        hasMore: _tradeHasMore,
                        onPressed: _loadMoreTrades,
                      ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 待同步外汇交易卡：本地临时行 + 失败原因 + 自动重试状态。
///
/// 临时行完全来自队列（不写服务端列表），推送成功后队列条目被移除，
/// 列表随 `lastSyncAt` 前进重新拉取，因此不会出现「临时 + 真实」两条。
class _PendingTradesCard extends StatelessWidget {
  const _PendingTradesCard({
    required this.entries,
    required this.outbox,
    required this.theme,
  });

  final List<OutboxEntry> entries;
  final OutboxController outbox;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bool headIsForex =
        outbox.entries.isNotEmpty &&
        outbox.entries.first.opType == outboxOpForexCreate;
    return SectionCard(
      title: '待同步',
      trailing: Text(
        '${entries.length} 笔',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: <Widget>[
          if (!outbox.isOnline)
            _QueueHint(
              icon: Icons.cloud_off_outlined,
              text: '当前无网络，恢复后按入队顺序自动推送',
            ),
          for (final OutboxEntry entry in entries)
            _PendingTradeRow(entry: entry),
          if (headIsForex && outbox.nextRetryAt != null)
            _QueueHint(
              icon: Icons.schedule_outlined,
              text: '下次自动重试：${_hm(outbox.nextRetryAt!)}',
            ),
          if (headIsForex && outbox.needsManualRetry)
            _QueueHint(
              icon: Icons.error_outline,
              text: '自动重试已达上限，请手动重试',
              color: theme.colorScheme.error,
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  outbox.isSyncing ? '正在同步…' : '按入队顺序推送，失败即停',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: outbox.isSyncing || !outbox.isOnline
                    ? null
                    : outbox.retryNow,
                child: const Text('立即同步'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 页内提示：图标 + 文案，可选错误色。
class _QueueHint extends StatelessWidget {
  const _QueueHint({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color contentColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(icon, size: 18, color: contentColor),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: contentColor),
          ),
        ),
      ],
    );
  }
}

/// 本地临时交易行：与真实交易相同的版式，额外带「待同步」角标。
class _PendingTradeRow extends StatelessWidget {
  const _PendingTradeRow({required this.entry});

  final OutboxEntry entry;

  /// 价格文案：百元以下保留 4 位，与真实交易一致。
  String _price(num value) {
    final double v = value.toDouble();
    return v.abs() >= 100 ? v.toStringAsFixed(2) : v.toStringAsFixed(4);
  }

  /// 手数文案：去掉无意义的 `.00`。
  String _lots(num value) {
    final String fixed = value.toDouble().toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final AppSemanticColors colors = context.semanticColors;
    final Map<String, dynamic> payload = entry.payload;
    final String symbol = payload['symbol'] as String? ?? '';
    final String orderType = payload['order_type'] as String? ?? 'buy';
    final num lotSize = payload['lot_size'] as num? ?? 0;
    final num openPrice = payload['open_price'] as num? ?? 0;
    final num? closePrice = payload['close_price'] as num?;
    final num? pnl = payload['pnl'] as num?;
    final num netPnl = (pnl ?? 0) +
        (payload['commission'] as num? ?? 0) +
        (payload['overnight_fee'] as num? ?? 0);
    final bool failed = entry.lastError != null;
    final String tradeDate = payload['trade_date'] as String? ?? '';
    final Color amountColor = netPnl > 0
        ? colors.success
        : (netPnl < 0 ? colors.danger : muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: <Widget>[
                Row(
                  spacing: 6,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        symbol.isEmpty ? '未命名交易' : symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      orderType == 'sell' ? '做空' : '做多',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: orderType == 'sell'
                            ? colors.warning
                            : colors.info,
                      ),
                    ),
                    const StatusChip(
                      label: '待同步',
                      tone: StatusTone.info,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: <Widget>[
                    Text(tradeDate, style: metaStyle),
                    Text('${_lots(lotSize)} 手', style: metaStyle),
                    Text('开 ${_price(openPrice)}', style: metaStyle),
                    if (closePrice != null)
                      Text('平 ${_price(closePrice)}', style: metaStyle),
                  ],
                ),
                if (failed)
                  Text(
                    entry.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                pnl == null ? '—' : formatUsdSigned(netPnl),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pnl == null ? muted : amountColor,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `HH:mm`：展示自动重试时间。
String _hm(DateTime time) {
  final DateTime local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// 资金四卡：累计出金 / 累计入金 / 体验金 / 净投入。
///
/// 数值用正文级大字（24 / 等宽数字），不用标签或徽章载体；
/// 375 + 1.3x 下由 [FittedBox] 等比缩放，不换行、不横向滚动。
class _FundMetrics extends StatelessWidget {
  const _FundMetrics({required this.stats});

  final FundStats? stats;

  @override
  Widget build(BuildContext context) {
    final AppSemanticColors colors = context.semanticColors;
    return Column(
      spacing: 12,
      children: <Widget>[
        Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: _FundMetric(
                label: '累计出金',
                value: formatUsd(stats?.withdraw),
                color: colors.danger,
              ),
            ),
            Expanded(
              child: _FundMetric(
                label: '累计入金',
                value: formatUsd(stats?.deposit),
                color: colors.success,
              ),
            ),
          ],
        ),
        Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: _FundMetric(
                label: '体验金',
                value: formatUsd(stats?.experience),
                color: colors.warning,
              ),
            ),
            Expanded(
              child: _FundMetric(
                label: '净投入',
                value: formatUsd(stats?.net),
                color: colors.info,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单个资金指标：大号数值 + 小号标签。
class _FundMetric extends StatelessWidget {
  const _FundMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: AppTypography.titleLarge.copyWith(
              color: color,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 单条资金明细：出金/入金/体验金 · 金额 · 日期 · 单号（四段一行）。
///
/// 金额右对齐、日期定宽、单号占剩余宽度并截断；完整单号通过 [Tooltip] 给出。
class _FundRow extends StatelessWidget {
  const _FundRow({required this.record, required this.onTap});

  final FundRecord record;

  /// 点击进入编辑页（左保存右删除）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Color typeColor;
    switch (record.recordType) {
      case 'deposit':
        typeColor = colors.success;
      case 'withdraw':
        typeColor = colors.danger;
      case 'experience':
        typeColor = colors.warning;
      default:
        typeColor = muted;
    }
    // 金额颜色跟随记录类型语义：入金绿、出金红、体验金琥珀，
    // 与左侧标签一致（出金不是收益，不能因为金额为正就染绿）。
    final Color amountColor;
    switch (record.recordType) {
      case 'deposit':
        amountColor = colors.success;
      case 'withdraw':
        amountColor = colors.danger;
      case 'experience':
        amountColor = colors.warning;
      default:
        amountColor = record.amount > 0
            ? colors.success
            : (record.amount < 0 ? colors.danger : muted);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 2,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        record.typeLabel,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: typeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatUsd(record.amount),
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // 单号与备注独占一行，避免在 375dp 上把备注挤成 `#209 · …`。
                  Text(
                    '${formatListDate(record.recordDate)} · ${record.orderNo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

/// 单笔交易：品种 + 方向 + 时间/手数/开平仓价，右侧净盈亏（正负分色）。
///
/// 负收益固定用 danger，绝不复用 success 色；点击进入编辑页（左保存右删除）。
class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade, required this.onTap});

  final ForexTrade trade;

  /// 点击进入编辑页。
  final VoidCallback onTap;

  /// 价格文案：百元以下保留 4 位，避免外汇报价失真。
  String _price(double value) {
    return value.abs() >= 100
        ? value.toStringAsFixed(2)
        : value.toStringAsFixed(4);
  }

  /// 手数文案：去掉无意义的 `.00`。
  String _lots(double value) {
    final String fixed = value.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final Color directionColor =
        trade.orderType == 'sell' ? colors.warning : colors.info;
    final Color amountColor = trade.netPnl > 0
        ? colors.success
        : (trade.netPnl < 0 ? colors.danger : muted);

    return InkWell(
      onTap: onTap,
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
                Row(
                  spacing: 6,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        trade.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      trade.orderTypeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: directionColor,
                      ),
                    ),
                  ],
                ),
                // 元信息用 Wrap：窄屏 / 1.3x 字体下换行而不是截断。
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: <Widget>[
                    Text(trade.timeText, style: metaStyle),
                    Text('${_lots(trade.lotSize)} 手', style: metaStyle),
                    Text('开 ${_price(trade.openPrice)}', style: metaStyle),
                    if (trade.closePrice != null)
                      Text('平 ${_price(trade.closePrice!)}', style: metaStyle),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formatUsdSigned(trade.netPnl),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: muted),
        ],
      ),
      ),
    );
  }
}

/// 资金按日三色柱图：入金 / 出金 / 体验金。
///
/// 规范落地：
/// - 单图一屏，360dp 内最多 12 组柱（超出取最近 12 组）；
/// - X 轴标签按容器宽度与字体缩放抽稀，避免 1.3x 下互相压字；
/// - 点按 / 长按 / 横向拖动选中某一天并给出读数（与收益曲线同交互）；
/// - 三色全部来自语义 token（success / danger / warning），不硬编码色值。
class _FundByDateChart extends StatefulWidget {
  const _FundByDateChart({required this.days});

  /// `by_date` 升序列表。
  final List<FundDayStat> days;

  @override
  State<_FundByDateChart> createState() => _FundByDateChartState();
}

class _FundByDateChartState extends State<_FundByDateChart> {
  static const int _maxBars = 12;

  /// 选中下标；为空时默认显示最近一天。
  int? _selected;

  /// 只保留有金额的日期，超出上限时取最近 12 组。
  List<FundDayStat> get _data {
    final List<FundDayStat> nonEmpty = widget.days
        .where((FundDayStat day) => !day.isEmpty)
        .toList();
    if (nonEmpty.length <= _maxBars) {
      return nonEmpty;
    }
    return nonEmpty.sublist(nonEmpty.length - _maxBars);
  }

  @override
  void didUpdateWidget(covariant _FundByDateChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 区间切换会换掉整份列表，旧下标对应的日期已不存在，回到最近一天。
    if (!identical(oldWidget.days, widget.days)) {
      _selected = null;
    }
  }

  /// 按横向位置换算选中组下标。
  void _pick(double dx, double groupWidth) {
    final int length = _data.length;
    if (length == 0 || groupWidth <= 0) {
      return;
    }
    final int index = (dx / groupWidth).floor().clamp(0, length - 1);
    if (index == _selected) {
      return;
    }
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final List<FundDayStat> data = _data;
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    final int index = (_selected ?? data.length - 1).clamp(0, data.length - 1);
    final FundDayStat current = data[index];
    final Color netColor = current.net > 0
        ? colors.success
        : (current.net < 0 ? colors.danger : muted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              current.date,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '净 ${formatUsdSigned(current.net)}',
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodySmall?.copyWith(
                color: netColor,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          children: <Widget>[
            Text(
              '入 ${formatUsd(current.deposit)}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.success),
            ),
            Text(
              '出 ${formatUsd(current.withdraw)}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
            Text(
              '体验 ${formatUsd(current.experience)}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
            ),
          ],
        ),
        // 提示放在图上：卡片末尾会被悬浮按钮遮挡。
        Text(
          data.length == _maxBars ? '最近 $_maxBars 个交易日 · 横向拖动查看' : '横向拖动查看每日读数',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double scale = MediaQuery.textScalerOf(context).scale(1);
            final int maxLabels = (constraints.maxWidth / (52 * scale))
                .floor()
                .clamp(2, 6);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails details) => _pick(
                details.localPosition.dx,
                constraints.maxWidth / data.length,
              ),
              onLongPressStart: (LongPressStartDetails details) => _pick(
                details.localPosition.dx,
                constraints.maxWidth / data.length,
              ),
              onHorizontalDragUpdate: (DragUpdateDetails details) => _pick(
                details.localPosition.dx,
                constraints.maxWidth / data.length,
              ),
              child: SizedBox(
                height: 168,
                child: CustomPaint(
                  painter: _FundByDatePainter(
                    data: data,
                    selected: index,
                    depositColor: colors.success,
                    withdrawColor: colors.danger,
                    experienceColor: colors.warning,
                    highlightColor: theme.colorScheme.primary,
                    baselineColor: theme.colorScheme.outlineVariant,
                    labelColor: muted,
                    labelStyle: theme.textTheme.bodySmall ?? const TextStyle(),
                    labelStep: (data.length / maxLabels).ceil(),
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 三色分组柱：正数向上、负数向下，零基线按数据范围定位。
class _FundByDatePainter extends CustomPainter {
  _FundByDatePainter({
    required this.data,
    required this.selected,
    required this.depositColor,
    required this.withdrawColor,
    required this.experienceColor,
    required this.highlightColor,
    required this.baselineColor,
    required this.labelColor,
    required this.labelStyle,
    required this.labelStep,
    required this.textScaler,
  });

  final List<FundDayStat> data;
  final int selected;
  final Color depositColor;
  final Color withdrawColor;
  final Color experienceColor;
  final Color highlightColor;
  final Color baselineColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final int labelStep;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }
    final double labelHeight = textScaler.scale(14);
    final double barsHeight = (size.height - labelHeight - 4).clamp(1, size.height);
    final double groupWidth = size.width / data.length;

    double maxValue = 0;
    double minValue = 0;
    for (final FundDayStat day in data) {
      for (final double value in <double>[
        day.deposit,
        day.withdraw,
        day.experience,
      ]) {
        if (value > maxValue) {
          maxValue = value;
        }
        if (value < minValue) {
          minValue = value;
        }
      }
    }
    final double span = maxValue - minValue;
    if (span <= 0) {
      return;
    }
    final double baselineY = barsHeight * (maxValue / span);
    final double unit = barsHeight / span;

    // 零基线
    final Paint baseline = Paint()
      ..color = baselineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      baseline,
    );

    final double barWidth = (groupWidth * 0.2).clamp(2.0, 9.0);
    const double gap = 1.5;

    for (int i = 0; i < data.length; i++) {
      final double center = groupWidth * (i + 0.5);
      if (i == selected) {
        final Paint highlight = Paint()
          ..color = highlightColor.withValues(alpha: 0.08);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(groupWidth * i, 0, groupWidth, barsHeight),
            const Radius.circular(6),
          ),
          highlight,
        );
      }
      final FundDayStat day = data[i];
      final List<({double value, Color color})> bars =
          <({double value, Color color})>[
            (value: day.deposit, color: depositColor),
            (value: day.withdraw, color: withdrawColor),
            (value: day.experience, color: experienceColor),
          ];
      final double totalWidth = bars.length * barWidth + (bars.length - 1) * gap;
      double x = center - totalWidth / 2;
      for (final ({double value, Color color}) bar in bars) {
        if (bar.value != 0) {
          final double height = (bar.value.abs() * unit).clamp(1.0, barsHeight);
          final double top = bar.value >= 0 ? baselineY - height : baselineY;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, top, barWidth, height),
              const Radius.circular(2),
            ),
            Paint()..color = bar.color,
          );
        }
        x += barWidth + gap;
      }
      // X 轴标签抽稀：首尾必显示，其余按步长。
      final bool showLabel =
          i % labelStep == 0 || i == data.length - 1;
      if (showLabel) {
        final String text = day.date.length >= 10
            ? day.date.substring(5)
            : day.date;
        final TextPainter painter = TextPainter(
          text: TextSpan(
            text: text,
            style: labelStyle.copyWith(color: labelColor, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textScaler: textScaler,
        )..layout(maxWidth: groupWidth * labelStep);
        painter.paint(
          canvas,
          Offset(
            center - painter.width / 2,
            barsHeight + (labelHeight - painter.height) / 2 + 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FundByDatePainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.data != data ||
        oldDelegate.depositColor != depositColor ||
        oldDelegate.baselineColor != baselineColor;
  }
}
