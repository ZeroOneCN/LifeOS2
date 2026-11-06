import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';

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
    await _refresh();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('交易已保存，列表与资金汇总已刷新')),
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
                  trailing: Text('共 $_tradeTotal 笔', style: trailingStyle),
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
  }
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
                value: formatMoney(stats?.withdraw),
                color: colors.danger,
              ),
            ),
            Expanded(
              child: _FundMetric(
                label: '累计入金',
                value: formatMoney(stats?.deposit),
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
                value: formatMoney(stats?.experience),
                color: colors.warning,
              ),
            ),
            Expanded(
              child: _FundMetric(
                label: '净投入',
                value: formatMoney(stats?.net),
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
                formatMoney(record.amount),
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
                trade.isOpen ? '持仓中' : formatMoney(trade.netPnl),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: trade.isOpen ? muted : amountColor,
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
