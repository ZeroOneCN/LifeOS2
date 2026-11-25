import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/models/report_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_status.dart';
import '../../shared/widgets/v2/domain_header.dart';
import '../../shared/widgets/v2/domain_tabs.dart';
import '../../shared/widgets/v2/hero_metric.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_icon_button.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_search.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_tokens.dart';
import '../reports/report_list_page.dart';
import 'forex_page.dart';
import 'invest_analysis_page.dart';
import 'invest_calendar_page.dart';

/// 投资中心 2.0 首屏：账户净值 Hero + 轻量收益曲线 + 盈亏/胜率/品种 + 交易概览。
///
/// 交易数据由网页端导入，移动端只读，因此本页不提供 FAB 写入入口。
/// 曲线只画累计净收益，不画账户净值；完整区间与逐点明细在「分析」页。
class InvestPage extends StatefulWidget {
  const InvestPage({super.key});

  @override
  State<InvestPage> createState() => _InvestPageState();
}

class _InvestPageState extends State<InvestPage> {
  static const List<_InvestTab> _tabs = <_InvestTab>[
    _InvestTab(label: '概览'),
    _InvestTab(label: '外汇', route: '/invest/forex'),
    _InvestTab(label: '分析', route: '/invest/forex/analysis'),
    _InvestTab(label: '日历', route: '/invest/forex/calendar'),
    _InvestTab(label: '报告', route: '/invest/reports'),
  ];

  int _activeTab = 0;
  int _rangeDays = 90;

  /// 已打开过的栏目：首次点击才构建页面，之后由 [IndexedStack] 保活。
  final Set<int> _visitedTabs = <int>{0};

  /// 点击栏目：内容就地切换，不再压栈跳转；切回概览时刷新一次摘要。
  void _openTab(int index) {
    if (index == _activeTab) {
      return;
    }
    final bool backToOverview = index == 0;
    setState(() {
      _activeTab = index;
      _visitedTabs.add(index);
    });
    if (backToOverview) {
      unawaited(AppScope.of(context).overview.refreshInvestment());
    }
  }

  /// 栏目序号 → 内容页。索引与 [_tabs] 一一对应。
  Widget _tabPage(int index) {
    switch (index) {
      case 1:
        return const ForexPage();
      case 2:
        return const InvestAnalysisPage();
      case 3:
        return const InvestCalendarPage();
      case 4:
        return const ReportListPage(source: ReportSource.investment);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _openSearch() async {
    final String? route = await openV2Search(
      context,
      hint: '搜索投资功能',
      sections: const <V2SearchSection>[
        V2SearchSection(
          title: '投资功能',
          entries: <V2SearchEntry>[
            V2SearchEntry(
              title: '外汇交易',
              subtitle: '交易明细与资金记录',
              icon: Icons.swap_horiz_outlined,
              route: '/invest/forex',
              keywords: '外汇 交易 资金 持仓',
            ),
            V2SearchEntry(
              title: '投资分析',
              subtitle: '胜率 · 盈亏比 · 品种分布',
              icon: Icons.insights_outlined,
              route: '/invest/forex/analysis',
              keywords: '分析 胜率 盈亏比 品种',
            ),
            V2SearchEntry(
              title: '交易日历',
              subtitle: '按日查看交易与盈亏',
              icon: Icons.calendar_month_outlined,
              route: '/invest/forex/calendar',
              keywords: '日历 交易 月份 盈亏',
            ),
            V2SearchEntry(
              title: '投资报告',
              subtitle: '周期汇总与 PDF 导出',
              icon: Icons.description_outlined,
              route: '/invest/reports',
              keywords: '报告 汇总 PDF 导出',
            ),
          ],
        ),
      ],
    );
    if (route != null && mounted) {
      // 搜索结果若是域内栏目，直接切到对应栏目，保持「不跳转」的一致体验。
      final int index = _tabs.indexWhere(
        (_InvestTab tab) => tab.route == route,
      );
      if (index > 0) {
        _openTab(index);
      } else {
        await context.push(route);
        if (mounted) {
          await AppScope.of(context).overview.refreshInvestment();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: scope.overview.investmentNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<InvestmentOverview> state =
            scope.overview.investment;
        final InvestmentOverview? data = state.data;
        final bool loading = data == null && state.status == LoadStatus.loading;
        final double? netProfit = data?.netProfit;
        final Color pnlColor = (netProfit ?? 0) >= 0
            ? tokens.green
            : tokens.red;
        final List<EquityPoint> points = _filteredPoints(data);

        return AnnotatedRegion<SystemUiOverlayStyle>(
            value: isDark
                ? SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: Colors.transparent,
                  )
                : SystemUiOverlayStyle.dark.copyWith(
                    statusBarColor: Colors.transparent,
                  ),
            child: Scaffold(
              backgroundColor: tokens.background,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: <Widget>[
                    DomainHeader(
                      title: '投资',
                      actions: <Widget>[
                        V2IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: '搜索投资功能',
                          onPressed: _openSearch,
                        ),
                        const NotificationBell(compact: true),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.pagePadding,
                      ),
                      child: DomainTabs(
                        labels: _tabs
                            .map((_InvestTab tab) => tab.label)
                            .toList(growable: false),
                        selectedIndex: _activeTab,
                        onSelected: _openTab,
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _activeTab,
                        children: <Widget>[
                          RefreshIndicator(
                            onRefresh: scope.overview.refreshInvestment,
                            color: tokens.accent,
                            backgroundColor: tokens.surface,
                            child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppTokens.pagePadding,
                            6,
                            AppTokens.pagePadding,
                            32,
                          ),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            if (state.status != LoadStatus.idle &&
                                state.status != LoadStatus.ready) ...<Widget>[
                              OverviewStatusBanner(
                                status: state.status,
                                message: state.message,
                                onRetry: scope.overview.retry,
                              ),
                              const SizedBox(height: 12),
                            ],
                            HeroMetric(
                              label: '账户净值',
                              value: loading
                                  ? '…'
                                  : formatUsd(
                                      data?.accountValue == null
                                          ? null
                                          : math.max(0, data!.accountValue!),
                                    ),
                              subtitle: _heroSubtitle(data, state.status),
                              subtitleColor: data == null ? null : pnlColor,
                            ),
                            const SizedBox(height: 14),
                            _EquityCard(
                              points: points,
                              rangeDays: _rangeDays,
                              color: pnlColor,
                              onRangeChanged: (int days) =>
                                  setState(() => _rangeDays = days),
                            ),
                            const SizedBox(height: 14),
                            StatRail(
                              items: <StatRailItem>[
                                StatRailItem(
                                  label: '累计净盈亏',
                                  value: loading
                                      ? '…'
                                      : _usdSignedCompact(netProfit),
                                  color: data == null ? null : pnlColor,
                                ),
                                StatRailItem(
                                  label: '胜率',
                                  value: loading
                                      ? '…'
                                      : formatPercent(data?.winRate),
                                ),
                                StatRailItem(
                                  label: '品种',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.symbolCount),
                                  unit: loading ? null : '个',
                                ),
                              ],
                            ),
                            SectionHeader(
                              title: '交易概览',
                              actionLabel: '报告',
                              onAction: () => _openTab(4),
                            ),
                            GroupCard(
                              children: <Widget>[
                                RecordRow(
                                  title: '近一年交易',
                                  subtitle: '按已平仓交易统计',
                                  value: '${formatInt(data?.tradeCount)} 笔',
                                  onTap: () => _openTab(1),
                                ),
                                RecordRow(
                                  title: '投资报告',
                                  subtitle: '周期汇总与 PDF 导出',
                                  value: '${formatInt(data?.reportCount)} 份',
                                  onTap: () => _openTab(4),
                                ),
                              ],
                            ),
                          ],
                        ),
                          ),
                          for (int i = 1; i < _tabs.length; i++)
                            if (_visitedTabs.contains(i))
                              DetailPageEmbedded(child: _tabPage(i))
                            else
                              const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
      },
    );
  }

  String _heroSubtitle(InvestmentOverview? data, LoadStatus status) {
    if (data == null) {
      return status == LoadStatus.loading ? '正在加载投资数据…' : '暂无数据，下拉刷新重试';
    }
    return '累计净盈亏 ${formatUsdSigned(data.netProfit)}';
  }

  /// 按当前区间过滤收益点；日期无法解析的点直接丢弃，避免曲线画错。
  List<EquityPoint> _filteredPoints(InvestmentOverview? data) {
    final List<EquityPoint> all = data?.equityTrend ?? const <EquityPoint>[];
    final DateTime cutoff = DateTime.now().subtract(
      Duration(days: _rangeDays - 1),
    );
    return all
        .where((EquityPoint point) {
          final DateTime? date = DateTime.tryParse(point.date);
          return date != null && !date.isBefore(cutoff);
        })
        .toList(growable: false);
  }

  /// 指标轨用的紧凑美元盈亏：`+$1,284` / `-$62`，避免两位小数把格子撑满。
  static String _usdSignedCompact(num? value) {
    if (value == null) {
      return '—';
    }
    final String sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign\$${formatInt(value.abs())}';
  }
}

/// 投资域栏目的静态定义。
class _InvestTab {
  const _InvestTab({required this.label, this.route});

  final String label;
  final String? route;
}

/// 轻量收益卡：区间切换 + 无坐标轴折线 + 极淡面积。
class _EquityCard extends StatelessWidget {
  const _EquityCard({
    required this.points,
    required this.rangeDays,
    required this.color,
    required this.onRangeChanged,
  });

  final List<EquityPoint> points;
  final int rangeDays;
  final Color color;
  final ValueChanged<int> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '累计净收益',
                  style: AppType.section.copyWith(color: tokens.text2),
                ),
              ),
              SizedBox(
                width: 132,
                child: V2Segmented<int>(
                  compact: true,
                  selected: rangeDays,
                  onChanged: onRangeChanged,
                  options: const <V2SegmentedOption<int>>[
                    V2SegmentedOption<int>(label: '30', value: 30),
                    V2SegmentedOption<int>(label: '90', value: 90),
                    V2SegmentedOption<int>(label: '1年', value: 365),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 86,
            child: points.length >= 2
                ? _Sparkline(points: points, color: color)
                : Center(
                    child: Text(
                      '暂无收益曲线',
                      style: AppType.rowMeta.copyWith(color: tokens.text3),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            '近 $rangeDays 天 · 按交易日累计（非账户净值）',
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.points, required this.color});

  final List<EquityPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(points: points, color: color),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});

  final List<EquityPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) {
      return;
    }
    double min = points.first.pnl;
    double max = points.first.pnl;
    for (final EquityPoint point in points) {
      min = math.min(min, point.pnl);
      max = math.max(max, point.pnl);
    }
    final double span = (max - min).abs() < 0.01 ? 1 : max - min;
    const double pad = 4;
    final double drawable = math.max(1, size.height - pad * 2);
    final double stepX = size.width / (points.length - 1);

    final Path line = Path();
    for (int i = 0; i < points.length; i++) {
      final double x = stepX * i;
      final double y = pad + (max - points[i].pnl) / span * drawable;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final Path area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
