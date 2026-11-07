import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/network/api_exception.dart';
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
/// - `equity_trend`：按交易日的**累计净收益**；该接口只返回近 365 天窗口，
///   因此「全部」区间单独调用 `GET /investment/forex/stats?days=3650` 取全量
///   （后端该接口支持最大 3650 天），仍按天展示、不聚合、不降采样。
///   它不是账户净值曲线，副标题与图注都需写明。
///
/// 交易明细在独立的「外汇交易」页（`/invest/forex`），这里提供明确入口。
class InvestPage extends StatefulWidget {
  const InvestPage({super.key});

  @override
  State<InvestPage> createState() => _InvestPageState();
}

class _InvestPageState extends State<InvestPage> {
  /// 收益曲线区间：30 / 90 / 365 天，0 表示「全部」（全量数据，仍按天）。
  int _rangeDays = 90;

  /// 当前选中的数据点下标；为空时默认指向区间最后一天。
  int? _selected;

  /// 「全部」区间的真全量曲线（来自 `/investment/forex/stats?days=3650`）。
  List<EquityPoint>? _fullPoints;
  bool _loadingFull = false;
  String? _fullError;

  bool get _isAll => _rangeDays == 0;

  String get _rangeLabel {
    switch (_rangeDays) {
      case 30:
        return '近 30 天';
      case 365:
        return '近 1 年';
      case 0:
        return '全部';
      default:
        return '近 90 天';
    }
  }

  /// 副标题：明确数据口径与覆盖范围，避免被误读成账户净值曲线。
  String get _subtitle {
    final List<EquityPoint>? full = _fullPoints;
    if (_isAll && full != null && full.isNotEmpty) {
      return '按交易日累计的净收益（非账户净值） · '
          '全部（${full.first.date} ~ ${full.last.date}） · 按天';
    }
    return '按交易日累计的净收益（非账户净值） · $_rangeLabel · 按天';
  }

  /// 拉取真全量曲线：切换「全部」时调用；失败保留旧数据并给出重试入口。
  Future<void> _loadFull() async {
    if (_loadingFull) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loadingFull = true;
      _fullError = null;
    });
    try {
      final Map<String, dynamic>? data =
          (await scope.apiClient.get<Map<String, dynamic>>(
        '/investment/forex/stats',
        queryParameters: <String, dynamic>{'days': 3650},
      ))
              .data;
      if (!mounted) {
        return;
      }
      final List<dynamic> trend =
          (data?['equity_trend'] as List<dynamic>?) ?? const <dynamic>[];
      setState(() {
        _fullPoints = trend
            .whereType<Map>()
            .map((Map item) =>
                EquityPoint.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false);
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _fullError = error.message);
    } finally {
      if (mounted) {
        setState(() => _loadingFull = false);
      }
    }
  }

  /// 按交易日切片；「全部」也按天保留每个点位，不按月合并、不降采样。
  List<EquityPoint> _series(List<EquityPoint> all) {
    if (all.isEmpty || _isAll) {
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
        final List<EquityPoint> points = _isAll
            ? (_fullPoints ?? const <EquityPoint>[])
            : _series(data?.equityTrend ?? const <EquityPoint>[]);
        // 未手动选择时默认指向区间最后一天；切换区间后同样回到最后一天。
        final int? selected = points.isEmpty
            ? null
            : (_selected != null && _selected! < points.length
                ? _selected
                : points.length - 1);

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
                  Text(
                    _subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 30, label: Text('30 天')),
                        ButtonSegment<int>(value: 90, label: Text('90 天')),
                        ButtonSegment<int>(value: 365, label: Text('1 年')),
                        ButtonSegment<int>(value: 0, label: Text('全部')),
                      ],
                      selected: <int>{_rangeDays},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                      onSelectionChanged: (Set<int> selection) {
                        // 换区间后读数回到新区间的最后一天，不残留旧点。
                        setState(() {
                          _rangeDays = selection.first;
                          _selected = null;
                        });
                        if (selection.first == 0) {
                          _loadFull();
                        }
                      },
                    ),
                  ),
                  if (_isAll && _loadingFull)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_isAll && _fullError != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: <Widget>[
                        Text(
                          '全量曲线加载失败：$_fullError',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                        AppSecondaryButton(
                          label: '重试',
                          compact: true,
                          onPressed: _loadFull,
                        ),
                      ],
                    ),
                  if (points.length < 2)
                    EmptyState(
                      icon: Icons.show_chart,
                      title: _isAll && _loadingFull
                          ? '正在加载全量数据'
                          : '该区间没有已平仓交易',
                      description: _isAll && _loadingFull
                          ? '按天读取历史累计净收益'
                          : '换一个区间查看，或等待新的平仓记录',
                      compact: true,
                    )
                  else
                    _EquityChart(
                      points: points,
                      muted: muted,
                      selected: selected,
                      onSelect: (int index) =>
                          setState(() => _selected = index),
                    ),
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
                    icon: Icons.candlestick_chart_outlined,
                    title: '外汇交易',
                    onTap: () => context.push('/invest/forex'),
                  ),
                  FeatureTile(
                    icon: Icons.insights_outlined,
                    title: '投资分析',
                    onTap: () => context.push('/invest/forex/analysis'),
                  ),
                  FeatureTile(
                    icon: Icons.calendar_month_outlined,
                    title: '交易日历',
                    onTap: () => context.push('/invest/forex/calendar'),
                  ),
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
///
/// 交互：点按选中最近的数据点；长按后拖动可连续逐日滑看（松手后保留读数）。
/// 横轴只标首尾与均分的关键日期，曲线本身保留每一个交易日的真实点位。
class _EquityChart extends StatelessWidget {
  const _EquityChart({
    required this.points,
    required this.muted,
    required this.selected,
    required this.onSelect,
  });

  final List<EquityPoint> points;
  final Color muted;

  /// 当前选中的下标（由父层维护，切换区间后默认指向最后一天）。
  final int? selected;
  final ValueChanged<int> onSelect;

  static const double _chartHeight = 152;
  static const double _padX = 4;

  /// 把横坐标换算成最近的数据点下标（点按与长按拖动共用）。
  void _selectAt(double dx, double width) {
    if (points.length < 2 || width <= _padX * 2) {
      return;
    }
    final double lineWidth = width - _padX * 2;
    final double ratio = ((dx - _padX) / lineWidth).clamp(0.0, 1.0);
    onSelect((ratio * (points.length - 1)).round());
  }

  /// 横轴标签抽稀：按可用宽度取 4 个等间距关键点，重复日期去重。
  List<String> _axisLabels(double width) {
    final int count = width >= 320 ? 4 : (width >= 220 ? 3 : 2);
    final List<String> labels = <String>[];
    for (int i = 0; i < count; i++) {
      final int index = ((points.length - 1) * i / (count - 1)).round();
      final int safe =
          index < 0 ? 0 : (index >= points.length ? points.length - 1 : index);
      final String date = points[safe].date;
      final String label =
          date.length >= 10 ? date.substring(5) : date;
      if (labels.isEmpty || labels.last != label) {
        labels.add(label);
      }
    }
    return labels;
  }

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
    final EquityPoint? current = selected == null ? null : points[selected!];
    final TextStyle? readoutStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Text(
          '最高 ${formatUsdSigned(maxValue)} · 最低 ${formatUsdSigned(minValue)}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        Text(
          current == null
              ? '点按或长按曲线查看单点数值'
              : '${current.date} · 累计 ${formatUsdSigned(current.pnl)}',
          style: current == null
              ? theme.textTheme.bodySmall?.copyWith(color: muted)
              : readoutStyle,
        ),
        SizedBox(
          height: _chartHeight,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails details) =>
                    _selectAt(details.localPosition.dx, width),
                onLongPressStart: (LongPressStartDetails details) =>
                    _selectAt(details.localPosition.dx, width),
                onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) =>
                    _selectAt(details.localPosition.dx, width),
                child: Semantics(
                  label: '收益曲线，点按或长按拖动查看单日数值',
                  child: CustomPaint(
                    size: Size(width, _chartHeight),
                    painter: _EquityCurvePainter(
                      values: points
                          .map((EquityPoint point) => point.pnl)
                          .toList(),
                      lineColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      gridColor: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                      successColor: AppColors.successLight,
                      dangerColor: theme.colorScheme.error,
                      minimum: minValue,
                      maximum: maxValue,
                      selectedIndex: selected,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final List<String> labels = _axisLabels(constraints.maxWidth);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                for (final String label in labels)
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            );
          },
        ),
        Text(
          '曲线为按交易日累计的净收益，不是账户净值；零线以上为盈利，以下为亏损。'
          '按住曲线横向拖动可逐日查看。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// 曲线绘制：面积按零线上下分别着色，折线中性色，零线用虚线。
/// 选中点额外画竖向虚线 + 实心圆点。
class _EquityCurvePainter extends CustomPainter {
  _EquityCurvePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.successColor,
    required this.dangerColor,
    required this.minimum,
    required this.maximum,
    this.selectedIndex,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final Color successColor;
  final Color dangerColor;
  final double minimum;
  final double maximum;
  final int? selectedIndex;

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

    // 选中点：竖向虚线定位 + 实心圆点。
    final int? index = selectedIndex;
    if (index != null && index >= 0 && index < points.length) {
      final Offset anchor = points[index];
      final Paint guidePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (double y = top; y < size.height - bottom; y += 7) {
        canvas.drawLine(
          Offset(anchor.dx, y),
          Offset(anchor.dx, math.min(y + 4, size.height - bottom)),
          guidePaint,
        );
      }
      canvas.drawCircle(anchor, 4, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _EquityCurvePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.minimum != minimum ||
        oldDelegate.maximum != maximum ||
        oldDelegate.selectedIndex != selectedIndex ||
        !listEquals(oldDelegate.values, values);
  }
}
