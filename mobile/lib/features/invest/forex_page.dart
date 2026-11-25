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
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';

/// 外汇交易：资金动态（摘要 + 柱图 + 明细）与交易记录（分页 + 净盈亏正负色）。
///
/// 数据（与网页端 `pages/investment/forex.tsx` 调用一致）：
/// - `GET /investment/funds/stats?start=&end=`：入金 / 出金 / 体验金 / 净投入 + 按日聚合；
/// - `GET /investment/funds?page=&page_size=20`：资金明细（接口不支持日期参数，区间内本地筛选）；
/// - `GET /investment/forex?page=&page_size=20&start=&end=`：交易记录。
///
/// 页内「统计区间」是唯一时间口径：资金摘要、三色柱图、资金明细与交易记录
/// 全部由同一个 `_rangeDays` 推导出的 `start` / `end` 拉取，避免两处区间不一致。
///
/// 行情与交易数据统一由网页端导入，移动端只读：本页不提供新增 / 编辑入口。
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

  /// 当前栏目：0 = 资金动态，1 = 交易记录；分段切换只换内容，不压栈。
  int _tab = 0;

  int _fundPage = 1;
  int _fundTotal = 0;
  bool _fundHasMore = false;
  bool _fundLoadingMore = false;

  int _tradePage = 1;
  int _tradeTotal = 0;
  bool _tradeHasMore = false;
  bool _tradeLoadingMore = false;

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
  /// 发生日期筛选，保证明细与摘要、柱图口径一致。
  Future<({List<FundRecord> items, int total, bool hasMore})> _loadFunds(
    AppScope scope,
  ) async {
    if (_rangeDays == 0) {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/investment/funds',
            queryParameters: <String, dynamic>{
              'page': 1,
              'page_size': _pageSize,
            },
          )).data;
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
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/investment/funds',
            queryParameters: <String, dynamic>{'page': page, 'page_size': 100},
          )).data;
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

  /// 切换统计区间：摘要、柱图、明细与交易记录使用同一组 `start` / `end` 重拉。
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
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/investment/funds',
            queryParameters: <String, dynamic>{
              'page': _fundPage + 1,
              'page_size': _pageSize,
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
        _fundPage += 1;
        _funds.addAll(_parseFunds(json));
        _fundTotal = (json['total'] as num?)?.toInt() ?? _funds.length;
        _fundHasMore = _funds.length < _fundTotal;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载更多失败：${error.message}')));
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
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/investment/forex',
            queryParameters: <String, dynamic>{
              ..._rangeParams,
              'page': _tradePage + 1,
              'page_size': _pageSize,
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
        _tradePage += 1;
        _trades.addAll(_parseTrades(json));
        _tradeTotal = (json['total'] as num?)?.toInt() ?? _trades.length;
        _tradeHasMore = _trades.length < _tradeTotal;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载更多失败：${error.message}')));
    } finally {
      if (mounted) {
        setState(() => _tradeLoadingMore = false);
      }
    }
  }

  /// 查看资金记录详情（只读，无编辑 / 删除入口）。
  Future<void> _openFundDetail(FundRecord record) async {
    await context.push<void>(
      '/invest/forex/funds/edit/${record.id}',
      extra: record,
    );
  }

  /// 查看交易详情（只读，无编辑 / 删除入口）。
  Future<void> _openTradeDetail(ForexTrade trade) async {
    await context.push<void>('/invest/forex/edit/${trade.id}', extra: trade);
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
    final bool offline =
        scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return DetailPageScaffold(
      title: '外汇交易',
      // 行情与资金数据统一由网页端导入：移动端不提供新增入口，
      // 因此页面没有底栏，也没有悬浮按钮。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          // 资金与交易是并列栏目：分段切换只换内容，不压栈、不跳转。
          V2Segmented<int>(
            options: const <V2SegmentedOption<int>>[
              V2SegmentedOption<int>(label: '资金动态', value: 0),
              V2SegmentedOption<int>(label: '交易记录', value: 1),
            ],
            selected: _tab,
            onChanged: (int value) => setState(() => _tab = value),
          ),
          _rangeBar(tokens),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: <Widget>[
                _fundTab(tokens),
                _tradeTab(tokens),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 统计区间控件：资金与交易共用同一口径，切换后统一重拉。
  Widget _rangeBar(AppTokens tokens) {
    return Row(
      children: <Widget>[
        Text('统计区间', style: AppType.rowMeta.copyWith(color: tokens.text2)),
        const Spacer(),
        SizedBox(
          width: 186,
          child: V2Segmented<int>(
            compact: true,
            options: const <V2SegmentedOption<int>>[
              V2SegmentedOption<int>(label: '近 30 天', value: 30),
              V2SegmentedOption<int>(label: '近 90 天', value: 90),
              V2SegmentedOption<int>(label: '全部', value: 0),
            ],
            selected: _rangeDays,
            onChanged: _setRange,
          ),
        ),
      ],
    );
  }

  /// 资金栏目：摘要 + 按日柱图 + 资金明细（分页）。
  Widget _fundTab(AppTokens tokens) {
    final FundStats? stats = _fundStats;
    // 业务规则：净值不可能为负，0 即代表账户已无余额。
    // 后端在区间口径下会给出负数（区间净投入 + 区间盈亏），展示层一律取 0 下限。
    final double? net = stats?.net;
    final double? netFloor = net == null ? null : (net < 0 ? 0 : net);
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        if (stats != null) ...<Widget>[
          SummaryStrip(
            caption: '$_rangeLabel · 共 ${formatInt(_fundTotal)} 笔资金 · '
                '体验金 ${_usdCompact(stats.experience)}',
            items: <StatRailItem>[
              StatRailItem(
                label: '累计入金',
                value: _usdCompact(stats.deposit),
                color: tokens.green,
              ),
              StatRailItem(
                label: '累计出金',
                value: _usdCompact(stats.withdraw),
                color: tokens.red,
              ),
              StatRailItem(
                label: '净投入',
                value: _usdCompact(netFloor),
                color: tokens.accent,
              ),
            ],
          ),
          if (stats.byDate.isNotEmpty) ...<Widget>[
            const SectionHeader(title: '资金动态'),
            // 图表卡继续用 SectionCard，交互与旧版保持一致。
            SectionCard(
              title: '按日资金',
              child: _FundByDateChart(days: stats.byDate),
            ),
          ],
          SectionHeader(title: '资金明细 · 共 ${formatInt(_fundTotal)} 笔'),
          GroupCard(
            children: _funds.isEmpty
                ? <Widget>[
                    EmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: _rangeDays == 0 ? '暂无资金记录' : '该区间没有资金记录',
                      description: _rangeDays == 0
                          ? '资金记录由网页端导入，移动端仅支持查看'
                          : '可切换上方「全部」查看历史记录',
                      compact: true,
                    ),
                  ]
                : <Widget>[
                    for (final FundRecord record in _funds)
                      _FundRow(
                        record: record,
                        onTap: () => _openFundDetail(record),
                      ),
                  ],
          ),
          Text(
            '口径：区间入金 − 出金（含体验金），展示下限为 \$0.00，'
            '这是「区间净投入 + 区间盈亏」口径，不是账户余额；'
            '摘要、柱图、明细与交易记录同口径，按发生日期倒序。',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
        ],
      ],
      footer: _funds.isNotEmpty
          ? ListLoadMoreFooter(
              loading: _fundLoadingMore,
              hasMore: _fundHasMore,
              onPressed: _loadMoreFunds,
            )
          : null,
    );
  }

  /// 交易栏目：交易笔数摘要 + 交易记录（分页，净盈亏正负分色）。
  Widget _tradeTab(AppTokens tokens) {
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SummaryStrip(
          caption: '$_rangeLabel · 按时间倒序 · 共 ${formatInt(_tradeTotal)} 笔交易',
          items: <StatRailItem>[
            StatRailItem(
              label: '交易笔数',
              value: formatInt(_tradeTotal),
              unit: '笔',
            ),
            StatRailItem(label: '统计区间', value: _rangeLabel),
          ],
        ),
        SectionHeader(title: '交易记录 · 共 ${formatInt(_tradeTotal)} 笔'),
        GroupCard(
          children: _trades.isEmpty
              ? <Widget>[
                  EmptyState(
                    icon: Icons.show_chart_outlined,
                    title: _rangeDays == 0 ? '暂无交易记录' : '该区间没有交易记录',
                    description: _rangeDays == 0
                        ? '交易数据由网页端导入，移动端仅支持查看'
                        : '可切换上方「全部」查看历史记录',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final ForexTrade trade in _trades)
                    _TradeRow(
                      trade: trade,
                      onTap: () => _openTradeDetail(trade),
                    ),
                ],
        ),
        Text(
          '交易数据由网页端导入，移动端仅支持查看；'
          '净盈亏已包含手续费与隔夜费。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
      footer: _trades.isNotEmpty
          ? ListLoadMoreFooter(
              loading: _tradeLoadingMore,
              hasMore: _tradeHasMore,
              onPressed: _loadMoreTrades,
            )
          : null,
    );
  }
}

/// 指标轨用的紧凑美元金额：`$1,284`（只保留整数），避免小数把格子撑破。
///
/// 明细行与图表读数仍用 [formatUsd] 保留两位小数，不丢精度。
String _usdCompact(num? value) {
  if (value == null) {
    return '—';
  }
  final String sign = value < 0 ? '-' : '';
  return '$sign\$${formatInt(value.abs())}';
}

/// 单条资金明细：日期 + 类型徽标在上，单号 + 金额在下。
///
/// 金额颜色跟随记录类型语义：入金绿、出金红、体验金琥珀；
/// 出金不是收益，不能因为金额为正就染绿。
class _FundRow extends StatelessWidget {
  const _FundRow({required this.record, required this.onTap});

  final FundRecord record;

  /// 点击进入只读详情。
  final VoidCallback onTap;

  /// 记录类型 → 徽标色调。
  static V2BadgeTone _tone(String type) {
    switch (type) {
      case 'deposit':
        return V2BadgeTone.green;
      case 'withdraw':
        return V2BadgeTone.danger;
      case 'experience':
        return V2BadgeTone.warn;
      default:
        return V2BadgeTone.gray;
    }
  }

  /// 记录类型 → 金额颜色（与徽标同一语义，出金不用绿色）。
  static Color _amountColor(AppTokens tokens, String type) {
    switch (type) {
      case 'deposit':
        return tokens.green;
      case 'withdraw':
        return tokens.red;
      case 'experience':
        return tokens.orange;
      default:
        return tokens.text2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: <Widget>[
              // 标题 + 类型徽标固定在上一行，数值放在下一行，行高整齐不抖动。
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      formatListDate(record.recordDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  V2Badge(record.typeLabel, tone: _tone(record.recordType)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 15, color: tokens.text3),
                ],
              ),
              Row(
                children: <Widget>[
                  // 单号与备注独占下一行左侧，避免把备注挤成 `#209 · …`。
                  Expanded(
                    child: Text(
                      record.orderNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      formatUsd(record.amount),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppType.rowValue.copyWith(
                        color: _amountColor(tokens, record.recordType),
                      ),
                    ),
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

/// 单笔交易：品种 + 方向徽标在上，时间/手数/开平仓价 + 净盈亏在下。
///
/// 负收益固定用红色，绝不复用绿色；点击进入只读详情。
class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade, required this.onTap});

  final ForexTrade trade;

  /// 点击进入只读详情。
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
    final AppTokens tokens = AppTokens.of(context);
    final Color amountColor = trade.netPnl > 0
        ? tokens.green
        : (trade.netPnl < 0 ? tokens.red : tokens.text2);
    // 元信息合并成一行副信息，窄屏 / 1.3x 下最多两行，不横向滚动。
    final String meta = <String>[
      trade.timeText,
      '${_lots(trade.lotSize)} 手',
      '开 ${_price(trade.openPrice)}',
      if (trade.closePrice != null) '平 ${_price(trade.closePrice!)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: <Widget>[
              // 品种 + 方向徽标固定在上一行，净盈亏放在下一行右侧。
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      trade.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  V2Badge(
                    trade.orderTypeLabel,
                    tone: trade.orderType == 'sell'
                        ? V2BadgeTone.warn
                        : V2BadgeTone.info,
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 15, color: tokens.text3),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      formatUsdSigned(trade.netPnl),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppType.rowValue.copyWith(color: amountColor),
                    ),
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
    final double barsHeight = (size.height - labelHeight - 4).clamp(
      1,
      size.height,
    );
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
      final double totalWidth =
          bars.length * barWidth + (bars.length - 1) * gap;
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
      final bool showLabel = i % labelStep == 0 || i == data.length - 1;
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
