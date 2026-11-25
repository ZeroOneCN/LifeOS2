import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';

/// 投资分析：账户指标 + 回撤/连胜 + 品种盈亏 + 时段分布。
///
/// 数据来源（与网页端 `pages/investment/forex.tsx` 的交易统计一致）：
/// - `GET /investment/forex/stats`。
///
/// 口径说明：后端 `stats` 的 `days` 是统一统计窗口（含今天），传入 3650
/// 即近十年，等同「全部已平仓交易」；汇总、品种盈亏、回撤、时段分布与
/// 收益曲线因此同口径，本页不提供区间切换，只按「账户 / 风险 / 分布」
/// 三个信息维度就地切换栏目（不跳转路由、不改数据请求）。
class InvestAnalysisPage extends StatefulWidget {
  const InvestAnalysisPage({super.key});

  @override
  State<InvestAnalysisPage> createState() => _InvestAnalysisPageState();
}

class _InvestAnalysisPageState extends State<InvestAnalysisPage> {
  ForexStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 当前栏目：0 账户、1 风险、2 分布。
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取统计；已有数据时保留旧数据避免页面闪空。
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
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/forex/stats',
                queryParameters: <String, dynamic>{'days': 3650},
              ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '统计接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = ForexStats.fromJson(json);
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _stats == null ? _errorStatus(scope, error) : LoadStatus.ready;
        _message = error.message;
      });
      if (_stats != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('统计刷新失败：${error.message}')),
        );
      }
    }
  }

  /// 错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
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
    final ForexStats? stats = _stats;
    final bool ready = _status == LoadStatus.ready || _status == LoadStatus.idle;

    return DetailPageScaffold(
      title: '投资分析',
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
              caption: _overviewCaption(stats),
              items: _summaryItems(stats),
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '账户', value: 0),
                V2SegmentedOption<int>(label: '风险', value: 1),
                V2SegmentedOption<int>(label: '分布', value: 2),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _accountTab(stats),
                  _riskTab(stats),
                  _distributionTab(stats),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 概览句：已平仓笔数、持仓与品种数。
  String _overviewCaption(ForexStats stats) {
    final ForexSummary summary = stats.summary;
    return '全部已平仓 ${formatInt(summary.tradeCount)} 笔 · '
        '持仓中 ${formatInt(summary.openCount)} 笔 · '
        '品种 ${formatInt(summary.symbolCount)} 个';
  }

  /// 概览指标轨：账户净值 / 净盈亏 / 胜率（笔数与品种在概览句中）。
  List<StatRailItem> _summaryItems(ForexStats stats) {
    final ForexSummary summary = stats.summary;
    return <StatRailItem>[
      StatRailItem(
        label: '账户净值',
        // 业务规则：净值不可能为负，展示下限 $0.00。
        value: formatUsd(
          summary.accountValue < 0 ? 0 : summary.accountValue,
        ),
      ),
      StatRailItem(
        label: '净盈亏',
        value: _usdCompact(summary.netProfit, signed: true),
        color: _pnlColor(context, summary.netProfit),
      ),
      StatRailItem(
        label: '胜率',
        value: formatPercent(summary.winRate),
      ),
    ];
  }

  /// 账户栏目：账户净值、盈亏与交易质量指标（全部已平仓交易口径）。
  Widget _accountTab(ForexStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    final ForexSummary summary = stats.summary;
    return ListPageBody(
      // 数据状态由外层统一处理，栏目内始终渲染已就绪的内容。
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '账户概览 · ${formatInt(summary.tradeCount)} 笔已平仓',
          actionLabel: '刷新',
          onAction: _refresh,
        ),
        GroupCard(
          children: <Widget>[
            RecordRow(
              title: '账户净值',
              value: formatUsd(
                summary.accountValue < 0 ? 0 : summary.accountValue,
              ),
            ),
            RecordRow(
              title: '净盈亏',
              value: formatUsdSigned(summary.netProfit),
              valueColor: _pnlColor(context, summary.netProfit),
            ),
            RecordRow(
              title: '交易笔数',
              value: '${formatInt(summary.tradeCount)} 笔',
            ),
            RecordRow(
              title: '持仓中',
              value: '${formatInt(summary.openCount)} 笔',
            ),
            RecordRow(title: '胜率', value: formatPercent(summary.winRate)),
            RecordRow(
              title: '盈亏比',
              // 与投资报告一致保留两位小数（报告显示 0.83，这里曾显示 0.8）。
              value: formatTwoDecimals(summary.profitLossRatio),
            ),
            RecordRow(
              title: '盈利因子',
              value: formatTwoDecimals(summary.profitFactor),
            ),
            RecordRow(
              title: '交易品种',
              value: '${formatInt(summary.symbolCount)} 个',
            ),
            RecordRow(title: '平均持仓', value: stats.analysis.avgHoldingText),
          ],
        ),
        Text(
          '账户概览为全部已平仓交易口径，不随统计区间变化。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 风险栏目：最大回撤、连胜连亏与平均盈亏。
  Widget _riskTab(ForexStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    final ForexAnalysis analysis = stats.analysis;
    final bool noDrawdownBase = analysis.maxDrawdownPct == null;
    return ListPageBody(
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '回撤与连胜 · 最长连赢 ${formatInt(analysis.longestWinStreak)} 笔',
          actionLabel: '刷新',
          onAction: _refresh,
        ),
        GroupCard(
          children: <Widget>[
            RecordRow(
              title: '最大回撤',
              value: formatUsd(analysis.maxDrawdown),
              valueColor: _pnlColor(context, -analysis.maxDrawdown),
            ),
            RecordRow(
              title: '最大回撤率',
              // 分母过小时后端返回 null：显示「—」而不是 0%。
              value: noDrawdownBase
                  ? '—'
                  : formatPercent(analysis.maxDrawdownPct),
              valueColor: noDrawdownBase
                  ? null
                  : _pnlColor(context, -analysis.maxDrawdownPct!),
            ),
            RecordRow(
              title: '最长连赢',
              value: '${formatInt(analysis.longestWinStreak)} 笔',
              valueColor: _pnlColor(context, 1),
            ),
            RecordRow(
              title: '最长连亏',
              value: '${formatInt(analysis.longestLossStreak)} 笔',
              valueColor: _pnlColor(context, -1),
            ),
            RecordRow(
              title: '平均盈利',
              value: analysis.avgWin == null
                  ? '—'
                  : formatUsd(analysis.avgWin),
              valueColor: analysis.avgWin == null
                  ? null
                  : _pnlColor(context, 1),
            ),
            RecordRow(
              title: '平均亏损',
              value: analysis.avgLoss == null
                  ? '—'
                  : formatUsd(analysis.avgLoss),
              valueColor: analysis.avgLoss == null
                  ? null
                  : _pnlColor(context, -1),
            ),
          ],
        ),
        Text(
          noDrawdownBase
              ? '累计净投入不超过 \$1，回撤率没有有效基准，显示为「—」；'
                  '回撤与连胜取全部已平仓交易。'
              : '回撤与连胜取全部已平仓交易，口径与网页端一致。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 分布栏目：品种盈亏与时段分布两张图表。
  Widget _distributionTab(ForexStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    final List<ForexSymbolStat> symbols = _topSymbols(stats.bySymbol);
    final List<ForexHourStat> hours = _hourBars(stats.analysis.hourDist);
    return ListPageBody(
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '品种盈亏 · 取 |盈亏| 前 ${formatInt(symbols.length)} 个',
          actionLabel: '刷新',
          onAction: _refresh,
        ),
        GroupCard(
          children: symbols.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.bar_chart_outlined,
                    title: '区间内暂无平仓交易',
                    description: '换一个更长的统计区间试试',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _PnlBars(items: symbols),
                  ),
                ],
        ),
        SectionHeader(
          title: '时段分布 · 取前 ${formatInt(hours.length)} 个时段',
        ),
        GroupCard(
          children: hours.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.schedule_outlined,
                    title: '区间内暂无交易时段数据',
                    description: '录入带开仓时间的交易后会在此汇总',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _CountBars(items: hours),
                  ),
                ],
        ),
        Text(
          '品种与时段分布取全部已平仓交易，柱长按最大值归一。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 按 |盈亏| 倒序取前 12，避免窄屏柱状图拥挤。
  List<ForexSymbolStat> _topSymbols(List<ForexSymbolStat> all) {
    final List<ForexSymbolStat> sorted = List<ForexSymbolStat>.of(all)
      ..sort((ForexSymbolStat a, ForexSymbolStat b) =>
          b.pnl.abs().compareTo(a.pnl.abs()));
    return sorted.take(12).toList();
  }

  /// 时段按笔数倒序取前 6。
  List<ForexHourStat> _hourBars(List<ForexHourStat> all) {
    final List<ForexHourStat> sorted = List<ForexHourStat>.of(all)
      ..sort((ForexHourStat a, ForexHourStat b) => b.count.compareTo(a.count));
    return sorted.take(6).toList();
  }

  /// 盈亏分色：正 success、负 danger、0 中性。
  Color _pnlColor(BuildContext context, double value) {
    final AppSemanticColors colors = context.semanticColors;
    if (value > 0) {
      return colors.success;
    }
    if (value < 0) {
      return colors.danger;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

/// 指标轨用的紧凑美元金额：`+$1,284`，只保留整数，避免格子被小数撑破。
String _usdCompact(num? value, {bool signed = false}) {
  if (value == null) {
    return '—';
  }
  final String sign = value < 0 ? '-' : (value > 0 && signed ? '+' : '');
  return '$sign\$${formatInt(value.abs())}';
}

/// 品种盈亏横条：柱长按最大 |pnl| 归一，正绿负红，右侧显示金额。
class _PnlBars extends StatelessWidget {
  const _PnlBars({required this.items});

  final List<ForexSymbolStat> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final double maxAbs = items.fold<double>(
      0,
      (double value, ForexSymbolStat item) =>
          item.pnl.abs() > value ? item.pnl.abs() : value,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: <Widget>[
        for (final ForexSymbolStat item in items)
          Row(
            children: <Widget>[
              SizedBox(
                width: 78,
                // 品种名长短不一（XAUUSD.rs / XAUUSDm），单行缩放不截断成 `XAUU…`。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.symbol,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double ratio =
                        maxAbs == 0 ? 0 : item.pnl.abs() / maxAbs;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 12,
                        width: (constraints.maxWidth * ratio).clamp(2, 1e9),
                        decoration: BoxDecoration(
                          color: item.pnl >= 0 ? colors.success : colors.danger,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatUsdSigned(item.pnl),
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: item.pnl >= 0 ? colors.success : colors.danger,
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
      ],
    );
  }
}

/// 时段笔数横条：柱长按最大笔数归一，中性主色。
class _CountBars extends StatelessWidget {
  const _CountBars({required this.items});

  final List<ForexHourStat> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int maxCount = items.fold<int>(
      0,
      (int value, ForexHourStat item) => item.count > value ? item.count : value,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: <Widget>[
        for (final ForexHourStat item in items)
          Row(
            children: <Widget>[
              SizedBox(
                width: 52,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double ratio =
                        maxCount == 0 ? 0 : item.count / maxCount;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 12,
                        width: (constraints.maxWidth * ratio).clamp(2, 1e9),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${item.count} 笔',
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
