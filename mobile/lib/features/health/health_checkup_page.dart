import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/read_only_notice.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import '../finance/finance_status_widgets.dart';

/// 体检指标：概览 + 异常/未判定/正常分组 + 指标历史展开（只读）。
///
/// 数据：`GET /health/checkup/stats?days=0`。
/// 指标最新值、状态、参考范围与历史趋势均来自该接口，不额外造接口。
///
/// 未采集/空值一律显示「—」；仅偏高/偏低使用警示色，正常保持中性。
class HealthCheckupPage extends StatefulWidget {
  const HealthCheckupPage({super.key});

  @override
  State<HealthCheckupPage> createState() => _HealthCheckupPageState();
}

class _HealthCheckupPageState extends State<HealthCheckupPage> {
  CheckupStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 当前展开历史的指标名；同一时间只展开一项，一屏最多一张折线。
  String? _expandedItem;

  /// 正常指标组默认收起，避免一屏几十条。
  bool _showNormal = false;

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

  /// 拉取体检统计（全部区间）；失败按登录态/网络/接口错误分流。
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
                '/health/checkup/stats',
                queryParameters: <String, dynamic>{'days': 0},
              ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '体检接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = CheckupStats.fromJson(json);
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final bool offline = scope.auth.hasLocalSession &&
          (error.kind == ApiErrorKind.network ||
              error.kind == ApiErrorKind.timeout);
      setState(() {
        _status = error.isUnauthorized
            ? LoadStatus.unauthenticated
            : (offline ? LoadStatus.connectionFailed : LoadStatus.failed);
        _message = error.message;
      });
    }
  }

  /// 展开/收起某项指标的历史；再点同一项则收起。
  void _toggleItem(String name) {
    setState(() {
      _expandedItem = _expandedItem == name ? null : name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final CheckupStats? stats = _stats;

    return DetailPageScaffold(
      title: '体检指标',
      child: ListView(
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
              const ReadOnlyNotice(),
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '体检概览',
                  trailing: Text(
                    '共 ${stats.items.length} 项 · ${stats.totalCount} 条',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: <Widget>[
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: _Metric(
                              label: '指标总数',
                              value: formatInt(stats.items.length),
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              label: '异常指标',
                              value: formatInt(stats.abnormalCount),
                              color: stats.abnormalCount > 0
                                  ? context.semanticColors.danger
                                  : null,
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              label: '检查记录',
                              value: formatInt(stats.totalCount),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${stats.statusLabel['high'] ?? '偏高'} ${stats.highCount} · '
                        '${stats.statusLabel['low'] ?? '偏低'} ${stats.lowCount} · '
                        '${stats.statusLabel['normal'] ?? '正常'} ${stats.normalCount}',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                if (stats.items.isEmpty)
                  SectionCard(
                    title: '体检指标',
                    child: const EmptyState(
                      icon: Icons.monitor_heart_outlined,
                      title: '暂无体检指标',
                      description: '还没有体检指标记录',
                      compact: true,
                    ),
                  )
                else ...<Widget>[
                  SectionCard(
                    title: '异常指标（${stats.abnormalCount}）',
                    child: _abnormalItems(stats).isEmpty
                        ? Text(
                            '当前所有指标均在参考范围内',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          )
                        : Column(
                            spacing: 4,
                            children: <Widget>[
                              for (final CheckupItem item
                                  in _abnormalItems(stats))
                                _CheckupRow(
                                  item: item,
                                  expanded: _expandedItem == item.itemName,
                                  statusLabel: _statusLabel(stats, item),
                                  onTap: () => _toggleItem(item.itemName),
                                ),
                            ],
                          ),
                  ),
                  if (_unknownItems(stats).isNotEmpty)
                    SectionCard(
                      title: '未判定指标（${_unknownItems(stats).length}）',
                      child: Column(
                        spacing: 4,
                        children: <Widget>[
                          for (final CheckupItem item in _unknownItems(stats))
                            _CheckupRow(
                              item: item,
                              expanded: _expandedItem == item.itemName,
                              statusLabel: _statusLabel(stats, item),
                              onTap: () => _toggleItem(item.itemName),
                            ),
                        ],
                      ),
                    ),
                  SectionCard(
                    title: '正常指标（${stats.normalCount}）',
                    trailing: TextButton(
                      onPressed: () =>
                          setState(() => _showNormal = !_showNormal),
                      child: Text(_showNormal ? '收起' : '展开'),
                    ),
                    child: _showNormal
                        ? Column(
                            spacing: 4,
                            children: <Widget>[
                              for (final CheckupItem item
                                  in _normalItems(stats))
                                _CheckupRow(
                                  item: item,
                                  expanded: _expandedItem == item.itemName,
                                  statusLabel: _statusLabel(stats, item),
                                  onTap: () => _toggleItem(item.itemName),
                                ),
                            ],
                          )
                        : Text(
                            '已收起 ${stats.normalCount} 项，点右上角「展开」查看',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 异常指标：偏高在前、偏低在后，同状态按名称排序。
List<CheckupItem> _abnormalItems(CheckupStats stats) {
  final List<CheckupItem> items = stats.items
      .where((CheckupItem item) => item.abnormal)
      .toList();
  items.sort((CheckupItem a, CheckupItem b) {
    final int rankA = a.latestResult == 'high' ? 0 : 1;
    final int rankB = b.latestResult == 'high' ? 0 : 1;
    if (rankA != rankB) {
      return rankA - rankB;
    }
    return a.itemName.compareTo(b.itemName);
  });
  return items;
}

/// 未判定指标（最新值为空或后端未给状态）。
List<CheckupItem> _unknownItems(CheckupStats stats) {
  return stats.items
      .where((CheckupItem item) =>
          item.latestResult == null || item.latestResult == 'unknown')
      .toList();
}

/// 正常指标，按名称排序。
List<CheckupItem> _normalItems(CheckupStats stats) {
  final List<CheckupItem> items = stats.items
      .where((CheckupItem item) => item.latestResult == 'normal')
      .toList();
  items.sort((CheckupItem a, CheckupItem b) => a.itemName.compareTo(b.itemName));
  return items;
}

/// 状态文案：优先用后端返回的中文，缺失时本地兜底。
String _statusLabel(CheckupStats stats, CheckupItem item) {
  final String? result = item.latestResult;
  if (result == null) {
    return '—';
  }
  return stats.statusLabel[result] ??
      switch (result) {
        'high' => '偏高',
        'low' => '偏低',
        'normal' => '正常',
        _ => result,
      };
}

/// 指标值展示：整数不带小数，其余最多两位并去掉末尾 0；null 显示「—」。
String _metricValue(double? value) {
  if (value == null) {
    return '—';
  }
  if (value == value.roundToDouble()) {
    return formatInt(value.round());
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 参考区间去掉无意义的尾随零：65.00-85.00 → 65-85，208.30 → 208.3。
String _trimReference(String text) {
  return text.replaceAllMapped(
    RegExp(r'\d+\.\d+'),
    (Match match) => _trimDecimal(match.group(0)!),
  );
}

String _trimDecimal(String value) {
  if (!value.contains('.')) {
    return value;
  }
  final String trimmed = value.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// 参考范围：接口优先，缺失时由上下限拼出；都没有显示「—」。
String _referenceText(CheckupItem item) {
  final String? raw = item.referenceRange?.trim();
  if (raw != null && raw.isNotEmpty) {
    return _trimReference(raw);
  }
  final double? low = item.refLow;
  final double? high = item.refHigh;
  if (low != null && high != null) {
    return '${_metricValue(low)}-${_metricValue(high)}';
  }
  if (low != null) {
    return '≥ ${_metricValue(low)}';
  }
  if (high != null) {
    return '≤ ${_metricValue(high)}';
  }
  return '—';
}

/// 概览数值块，支持异常时传警示色；数字等宽。
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 指标行：名称 + 状态、最新值 + 单位、参考范围；点击展开历史。
class _CheckupRow extends StatelessWidget {
  const _CheckupRow({
    required this.item,
    required this.expanded,
    required this.statusLabel,
    required this.onTap,
  });

  final CheckupItem item;
  final bool expanded;
  final String statusLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Color? valueColor = _valueColor(context, item.latestResult);
    final String unit = (item.unit ?? '').trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: <Widget>[
            Row(
              spacing: 6,
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.itemName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusBadge(result: item.latestResult, label: statusLabel),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: muted,
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      TextSpan(
                        text: '最新 ',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted),
                      ),
                      TextSpan(
                        text: _metricValue(item.latestValue),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: valueColor,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 单位单独成块且不换行：mL/(min*1.73m²) 这类长单位不再被
                // 拆成「mL/（min*1.」两截。
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    softWrap: false,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                Text(
                  '参考 ${_referenceText(item)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            if (expanded)
              _CheckupHistory(
                item: item,
                valueColor: valueColor,
              ),
          ],
        ),
      ),
    );
  }
}

/// 状态标签：偏高红、偏低橙、正常与未判定保持中性文字。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.result, required this.label});

  final String? result;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    switch (result) {
      case 'high':
        return StatusChip(label: label, tone: StatusTone.danger);
      case 'low':
        return StatusChip(label: label, tone: StatusTone.warning);
      default:
        return Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
    }
  }
}

/// 偏高用危险色、偏低用警告色、正常/空值中性。
Color? _valueColor(BuildContext context, String? result) {
  final AppSemanticColors colors = context.semanticColors;
  switch (result) {
    case 'high':
      return colors.danger;
    case 'low':
      return colors.warning;
    default:
      return null;
  }
}

/// 展开的历史：最近 N 次记录（新→旧）+ 单条折线（仅一项展开，最多一张）。
class _CheckupHistory extends StatelessWidget {
  const _CheckupHistory({
    required this.item,
    required this.valueColor,
  });

  final CheckupItem item;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final int shown = item.trend.length;
    final List<double> chartValues = item.trend
        .where((CheckupTrendPoint point) => point.value != null)
        .map((CheckupTrendPoint point) => point.value!)
        .toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '历史记录',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              Text(
                item.count > shown ? '共 ${item.count} 次 · 最近 $shown 次' : '共 ${item.count} 次',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          if (chartValues.length >= 2) ...<Widget>[
            SizedBox(
              height: 56,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: chartValues,
                  lineColor: muted,
                  pointColor: valueColor ?? muted,
                ),
              ),
            ),
            Text(
              '最近 $shown 次趋势',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (shown == 0)
            Text(
              '无历史明细',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            )
          else
            for (final CheckupTrendPoint point in item.trend.reversed)
              Row(
                spacing: 12,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      point.date,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  Text(
                    _metricValue(point.value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _valueColor(context, point.result),
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  Text(
                    _pointLabel(point.result),
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  /// 历史点状态文案；缺失时显示「—」，不使用行首面的状态（那是最新值）。
  String _pointLabel(String? result) {
    if (result == null) {
      return '—';
    }
    return switch (result) {
      'high' => '偏高',
      'low' => '偏低',
      'normal' => '正常',
      _ => result,
    };
  }
}

/// 单条折线：按最小值/最大值等比映射到画布，仅绘制折线与点，不画坐标轴。
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.lineColor,
    required this.pointColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color pointColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }
    double minValue = values.first;
    double maxValue = values.first;
    for (final double value in values) {
      if (value < minValue) {
        minValue = value;
      }
      if (value > maxValue) {
        maxValue = value;
      }
    }
    const double padding = 6;
    final double usableWidth = size.width - padding * 2;
    final double usableHeight = size.height - padding * 2;
    final double span = maxValue - minValue;

    final List<Offset> points = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(
          padding + usableWidth * (i / (values.length - 1)),
          span == 0
              ? size.height / 2
              : padding + usableHeight * (1 - (values[i] - minValue) / span),
        ),
    ];

    final Paint linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);

    final Paint dotPaint = Paint()..color = pointColor;
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], i == points.length - 1 ? 3 : 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.pointColor != pointColor ||
        !listEquals(oldDelegate.values, values);
  }
}
