import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/queue/outbox_controller.dart';
import '../../core/queue/outbox_entry.dart';
import '../../core/utils/formatters.dart';
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
/// - `GET /investment/funds/stats`：累计入金 / 出金 / 体验金 / 净投入；
/// - `GET /investment/funds?page=&page_size=20`：资金明细；
/// - `GET /investment/forex?page=&page_size=20`：交易记录。
///
/// 新增交易从本页 FAB 进入 `/invest/forex/new`，保存成功后回到本页并刷新汇总。
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
              .get<Map<String, dynamic>>('/investment/funds/stats')
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/funds',
                queryParameters: <String, dynamic>{
                  'page': 1,
                  'page_size': _pageSize,
                },
              )
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/forex',
                queryParameters: <String, dynamic>{
                  'page': 1,
                  'page_size': _pageSize,
                },
              )
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? fundJson =
          responses[1] as Map<String, dynamic>?;
      final Map<String, dynamic>? tradeJson =
          responses[2] as Map<String, dynamic>?;
      if (statsJson == null || fundJson == null || tradeJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '资金或交易接口返回数据为空',
        );
      }
      final List<FundRecord> funds = _parseFunds(fundJson);
      final List<ForexTrade> trades = _parseTrades(tradeJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _fundStats = FundStats.fromJson(statsJson);
        _funds
          ..clear()
          ..addAll(funds);
        _trades
          ..clear()
          ..addAll(trades);
        _fundPage = 1;
        _fundTotal = (fundJson['total'] as num?)?.toInt() ?? funds.length;
        _fundHasMore = _funds.length < _fundTotal;
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            label: const Text('新增交易'),
          ),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
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
                      trailing: Text('共 $_fundTotal 笔', style: trailingStyle),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: <Widget>[
                          _FundMetrics(stats: _fundStats),
                          if (_funds.isEmpty)
                            const EmptyState(
                              icon: Icons.account_balance_wallet_outlined,
                              title: '暂无资金记录',
                              description: '入金 / 出金 / 体验金可在网页端录入',
                              compact: true,
                            )
                          else
                            Column(
                              children: <Widget>[
                                for (final FundRecord record in _funds)
                                  _FundRow(record: record),
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
                        pending.isEmpty
                            ? '共 $_tradeTotal 笔'
                            : '共 $_tradeTotal 笔 · 待同步 ${pending.length}',
                        style: trailingStyle,
                      ),
                      child: _trades.isEmpty
                          ? const EmptyState(
                              icon: Icons.show_chart_outlined,
                              title: '暂无交易记录',
                              description: '点击右下角「新增交易」录入第一笔',
                              compact: true,
                            )
                          : Column(
                              children: <Widget>[
                                for (final ForexTrade trade in _trades)
                                  _TradeRow(trade: trade),
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
  const _FundRow({required this.record});

  final FundRecord record;

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
    final Color amountColor = record.amount > 0
        ? colors.success
        : (record.amount < 0 ? colors.danger : muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 50,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                record.typeLabel,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: typeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
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
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                record.recordDate,
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
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: record.orderNo,
              child: Text(
                record.orderNo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单笔交易：品种 + 方向 + 时间/手数/开平仓价，右侧净盈亏（正负分色）。
///
/// 负收益固定用 danger，绝不复用 success 色。
class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final ForexTrade trade;

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

    return Padding(
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
        ],
      ),
    );
  }
}
