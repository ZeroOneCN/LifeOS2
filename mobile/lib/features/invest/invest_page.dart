import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feature_entries.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// 投资中心根页：账户概览 → 收益曲线 → 常用（外汇交易）→ 全部功能 → 交易概览。
///
/// 摘要与收益曲线来自 `GET /investment/overview`：
/// - `summary`：账户净值、累计净盈亏、胜率、品种数（金额口径为 USD）；
/// - `equity_trend`：按交易日的**累计净收益**（后端固定返回近 365 天窗口），
///   页面只按 30 / 90 / 365 天做前端区间切片，不重算、不拼凑。
///
/// 交易明细在独立的「外汇交易」页（`/invest/forex`），这里提供明确入口。
class InvestPage extends StatefulWidget {
  const InvestPage({super.key});

  @override
  State<InvestPage> createState() => _InvestPageState();
}

class _InvestPageState extends State<InvestPage> {
  /// 收益曲线区间：30 / 90 / 365 天（后端最多提供近一年）。
  int _rangeDays = 90;

  String get _rangeLabel {
    switch (_rangeDays) {
      case 30:
        return '近 30 天';
      case 365:
        return '近 1 年';
      default:
        return '近 90 天';
    }
  }

  /// 按交易日字符串（YYYY-MM-DD）过滤区间；曲线本身是累计值，只切片不重算。
  List<EquityPoint> _window(List<EquityPoint> all) {
    if (all.isEmpty) {
      return all;
    }
    final DateTime cutoff =
        DateTime.now().subtract(Duration(days: _rangeDays - 1));
    final String cutoffText = _dateText(cutoff);
    return all
        .where((EquityPoint point) => point.date.compareTo(cutoffText) >= 0)
        .toList(growable: false);
  }

  static String _dateText(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;

    return ListenableBuilder(
      listenable: scope.overview.investmentNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<InvestmentOverview> state =
            scope.overview.investment;
        final InvestmentOverview? data = state.data;
        final double? netProfit = data?.netProfit;
        final List<EquityPoint> points = _window(
          data?.equityTrend ?? const <EquityPoint>[],
        );

        return RootPageScaffold(
          title: '投资中心',
          children: <Widget>[
            OverviewStatusBanner(
              status: state.status,
              message: state.message,
              onRetry: scope.overview.retry,
            ),
            SectionCard(
              title: '账户概览',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: <Widget>[
                  Row(
                    spacing: 24,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: <Widget>[
                            Text(
                              formatUsd(data?.accountValue),
                              style: AppTypography.amountLarge,
                            ),
                            Text(
                              '账户净值',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 4,
                          children: <Widget>[
                            Text(
                              formatUsdSigned(netProfit),
                              style: AppTypography.amountLarge.copyWith(
                                color: netProfit == null
                                    ? null
                                    : (netProfit >= 0
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.error),
                              ),
                            ),
                            Text(
                              '累计盈亏',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '收益曲线',
              trailing: points.isEmpty
                  ? null
                  : Text(
                      formatUsdSigned(points.last.pnl),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: points.last.pnl < 0
                            ? AppColors.dangerLight
                            : (points.last.pnl > 0
                                ? AppColors.successLight
                                : muted),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '累计净收益 · $_rangeLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                      SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                          ButtonSegment<int>(value: 30, label: Text('30 天')),
                          ButtonSegment<int>(value: 90, label: Text('90 天')),
                          ButtonSegment<int>(value: 365, label: Text('1 年')),
                        ],
                        selected: <int>{_rangeDays},
                        showSelectedIcon: false,
                        onSelectionChanged: (Set<int> selection) {
                          setState(() => _rangeDays = selection.first);
                        },
                      ),
                    ],
                  ),
                  if (points.length < 2)
                    const EmptyState(
                      icon: Icons.show_chart,
                      title: '该区间没有已平仓交易',
                      description: '换一个区间查看，或等待新的平仓记录',
                      compact: true,
                    )
                  else
                    _EquityChart(points: points, muted: muted),
                ],
              ),
            ),
            SectionCard(
              title: '常用',
              child: PrimaryFeatureCard(
                icon: Icons.candlestick_chart_outlined,
                title: '外汇交易',
                summary: '近一年 ${formatInt(data?.tradeCount)} 笔 · '
                    '报告 ${formatInt(data?.reportCount)} 份',
                onTap: () => context.push('/invest/forex'),
              ),
            ),
            SectionCard(
              title: '全部功能',
              child: FeatureGrid(
                children: <Widget>[
                  FeatureTile(
                    icon: Icons.description_outlined,
                    title: '投资报告',
                    onTap: () => context.push('/invest/reports'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '交易概览',
              child: Row(
                spacing: 16,
                children: <Widget>[
                  Expanded(
                    child: MetricPlaceholder(
                      label: '胜率',
                      value: formatPercent(data?.winRate),
                    ),
                  ),
                  Expanded(
                    child: MetricPlaceholder(
                      label: '交易品种',
                      value: formatInt(data?.symbolCount),
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '近期交易',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: <Widget>[
                  Text(
                    state.status == LoadStatus.unauthenticated
                        ? '登录后可查看近一年外汇交易明细。'
                        : '外汇交易明细已接入：可查看近一年全部交易、按币种筛选并新增交易。',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  AppPrimaryButton(
                    label: '查看交易明细',
                    icon: Icons.show_chart,
                    onPressed: () => context.push('/invest/forex'),
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

/// 收益曲线：中性折线 + 零线以上绿色面积 / 零线以下红色面积，不染整块背景。
class _EquityChart extends StatelessWidget {
  const _EquityChart({required this.points, required this.muted});

  final List<EquityPoint> points;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    double maxValue = 0;
    double minValue = 0;
    for (final EquityPoint point in points) {
      if (point.pnl > maxValue) {
        maxValue = point.pnl;
      }
      if (point.pnl < minValue) {
        minValue = point.pnl;
      }
    }
    final String firstDate = points.first.date.length >= 10
        ? points.first.date.substring(5)
        : points.first.date;
    final String lastDate = points.last.date.length >= 10
        ? points.last.date.substring(5)
        : points.last.date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Text(
          '最高 ${formatUsdSigned(maxValue)} · 最低 ${formatUsdSigned(minValue)}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        SizedBox(
          height: 152,
          child: CustomPaint(
            painter: _EquityCurvePainter(
              values: points.map((EquityPoint point) => point.pnl).toList(),
              lineColor: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              gridColor: theme.colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
              successColor: AppColors.successLight,
              dangerColor: theme.colorScheme.error,
              minimum: minValue,
              maximum: maxValue,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              firstDate,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            Text(
              lastDate,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        Text(
          '零线以上为盈利，以下为亏损；曲线为按交易日的累计净收益，不是账户净值。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// 曲线绘制：面积按零线上下分别着色，折线中性色，零线用虚线。
class _EquityCurvePainter extends CustomPainter {
  _EquityCurvePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.successColor,
    required this.dangerColor,
    required this.minimum,
    required this.maximum,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final Color successColor;
  final Color dangerColor;
  final double minimum;
  final double maximum;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }
    const double left = 4;
    const double right = 4;
    const double top = 6;
    const double bottom = 6;
    final double usableWidth = size.width - left - right;
    final double usableHeight = size.height - top - bottom;
    final double span = maximum - minimum;
    double yOf(double value) {
      if (span == 0) {
        return top + usableHeight / 2;
      }
      return top + usableHeight * (1 - (value - minimum) / span);
    }

    final double zeroY = yOf(0);
    final Paint gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // 三条水平网格线：最高 / 零 / 最低。
    for (final double value in <double>[maximum, 0, minimum]) {
      final double y = yOf(value);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // 零线虚线强调。
    final Paint zeroPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, zeroY), Offset(x + 4, zeroY), zeroPaint);
    }

    final List<Offset> points = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(
          left + usableWidth * (i / (values.length - 1)),
          yOf(values[i]),
        ),
    ];
    final Path line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final Path area = Path.from(line)
      ..lineTo(points.last.dx, zeroY)
      ..lineTo(points.first.dx, zeroY)
      ..close();
    // 只给前景面积着色：零线以上绿、以下红，不染整块背景。
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, zeroY));
    canvas.drawPath(
      area,
      Paint()..color = successColor.withValues(alpha: 0.16),
    );
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, zeroY, size.width, size.height));
    canvas.drawPath(
      area,
      Paint()..color = dangerColor.withValues(alpha: 0.16),
    );
    canvas.restore();

    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // 起点 / 终点圆点，标出区间边界。
    final Paint dotPaint = Paint()..color = lineColor;
    canvas.drawCircle(points.first, 2.5, dotPaint);
    canvas.drawCircle(points.last, 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _EquityCurvePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.minimum != minimum ||
        oldDelegate.maximum != maximum ||
        !listEquals(oldDelegate.values, values);
  }
}
