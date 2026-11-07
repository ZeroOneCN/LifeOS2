import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';

/// 投资分析：账户指标 + 回撤/连胜 + 品种盈亏 + 时段分布。
///
/// 数据来源（与网页端 `pages/investment/forex.tsx` 的交易统计一致）：
/// - `GET /investment/forex/stats`。
///
/// 口径说明：后端 `stats` 的 `days` 是统一统计窗口（含今天），传入 3650
/// 即近十年，等同「全部已平仓交易」；汇总、品种盈亏、回撤、时段分布与
/// 收益曲线因此同口径，本页不提供区间切换。
class InvestAnalysisPage extends StatefulWidget {
  const InvestAnalysisPage({super.key});

  @override
  State<InvestAnalysisPage> createState() => _InvestAnalysisPageState();
}

class _InvestAnalysisPageState extends State<InvestAnalysisPage> {
  ForexStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取统计；切换区间时保留旧数据避免页面闪空。
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
    final ThemeData theme = Theme.of(context);
    final ForexStats? stats = _stats;

    return DetailPageScaffold(
      title: '投资分析',
      actions: <Widget>[
        IconButton(
          tooltip: '刷新',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
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
                  title: '账户概览',
                  // 后端汇总不按区间过滤，明确标注口径，避免和收益曲线的区间混淆。
                  trailing: Text(
                    '全部已平仓交易',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: _MetricGrid(
                    items: <({String label, String value, Color? color})>[
                      (
                        label: '账户净值',
                        value: formatUsd(stats.summary.accountValue),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '净盈亏',
                        value: formatUsdSigned(stats.summary.netProfit),
                        color: _pnlColor(context, stats.summary.netProfit),
                      ),
                      (
                        label: '交易笔数',
                        value: formatInt(stats.summary.tradeCount),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '持仓中',
                        value: formatInt(stats.summary.openCount),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '胜率',
                        value: formatPercent(stats.summary.winRate),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '盈亏比',
                        // 与投资报告一致保留两位小数（报告显示 0.83，这里曾显示 0.8）。
                        value: formatTwoDecimals(stats.summary.profitLossRatio),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '盈利因子',
                        value: formatTwoDecimals(stats.summary.profitFactor),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '交易品种',
                        value: formatInt(stats.summary.symbolCount),
                        color: theme.colorScheme.onSurface,
                      ),
                      (
                        label: '平均持仓',
                        value: stats.analysis.avgHoldingText,
                        color: theme.colorScheme.onSurface,
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '回撤与连胜',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _MetricGrid(
                        items: <({String label, String value, Color? color})>[
                          (
                            label: '最大回撤',
                            value: formatUsd(stats.analysis.maxDrawdown),
                            color: _pnlColor(
                              context,
                              -stats.analysis.maxDrawdown,
                            ),
                          ),
                          (
                            label: '最大回撤率',
                            // 分母过小时后端返回 null：显示「—」而不是 0%。
                            value: stats.analysis.maxDrawdownPct == null
                                ? '—'
                                : formatPercent(stats.analysis.maxDrawdownPct),
                            color: stats.analysis.maxDrawdownPct == null
                                ? theme.colorScheme.onSurfaceVariant
                                : _pnlColor(
                                    context,
                                    -stats.analysis.maxDrawdownPct!,
                                  ),
                          ),
                          (
                            label: '最长连赢',
                            value: '${stats.analysis.longestWinStreak} 笔',
                            color: _pnlColor(context, 1),
                          ),
                          (
                            label: '最长连亏',
                            value: '${stats.analysis.longestLossStreak} 笔',
                            color: _pnlColor(context, -1),
                          ),
                          (
                            label: '平均盈利',
                            value: stats.analysis.avgWin == null
                                ? '—'
                                : formatUsd(stats.analysis.avgWin),
                            color: _pnlColor(context, 1),
                          ),
                          (
                            label: '平均亏损',
                            value: stats.analysis.avgLoss == null
                                ? '—'
                                : formatUsd(stats.analysis.avgLoss),
                            color: _pnlColor(context, -1),
                          ),
                        ],
                      ),
                      if (stats.analysis.maxDrawdownPct == null) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          '累计净投入不超过 \$1，回撤率没有有效基准，显示为「—」。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SectionCard(
                  title: '品种盈亏',
                  trailing: Text(
                    '按 |盈亏| 取前 12',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: stats.bySymbol.isEmpty
                      ? const EmptyState(
                          icon: Icons.bar_chart_outlined,
                          title: '区间内暂无平仓交易',
                          description: '换一个更长的统计区间试试',
                          compact: true,
                        )
                      : _PnlBars(items: _topSymbols(stats.bySymbol)),
                ),
                SectionCard(
                  title: '时段分布',
                  trailing: Text(
                    '按交易笔数取前 6',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: _hourBars(stats.analysis.hourDist).isEmpty
                      ? const EmptyState(
                          icon: Icons.schedule_outlined,
                          title: '区间内暂无交易时段数据',
                          description: '录入带开仓时间的交易后会在此汇总',
                          compact: true,
                        )
                      : _CountBars(items: _hourBars(stats.analysis.hourDist)),
                ),
              ],
            ],
          ),
        ],
      ),
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

/// 指标网格：两列、标签在上、数值在下，数值单行缩放。
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<({String label, String value, Color? color})> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 8;
        final double width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final ({String label, String value, Color? color}) item
                in items)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: <Widget>[
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.value,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: item.color,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
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
