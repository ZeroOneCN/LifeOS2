import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 体重记录页：与网页端 `/health/body` 同源。
///
/// 数据（`GET /health/body`、`GET /health/body/stats?days=0`）：
/// - 概览：当前体重 / BMI / 体脂率 / 平均体重，取自后端统计接口；
/// - 趋势：体重折线，点按或长按横向拖动逐日读数（与收益曲线同一套交互）；
/// - 历史：按日期倒序，点按进入编辑（编辑页左保存、右删除）。
///
/// 展示口径：后端把「未采集」写成 0 或 null（如 `muscle_percent = 0`、
/// `height_cm = 0`），一律显示「—」，不把 0 当真实测量值。
///
/// 历史列表的加载方式：后端响应模型对 `height_cm / weight_kg / bmi` 施加了
/// `gt=0` 约束，历史数据里只要有一条 `height_cm = 0`（实测 1 条：id=20），
/// 包含它的**整页**就会 500。因此这里不按页码翻页，而是按 `start`/`end`
/// 日期窗口一次取全量，遇到 500 就把日期窗口二分降级，最终只跳过
/// 真正无法序列化的那一天，其它记录照常展示。
class HealthBodyPage extends StatefulWidget {
  const HealthBodyPage({super.key});

  @override
  State<HealthBodyPage> createState() => _HealthBodyPageState();
}

class _HealthBodyPageState extends State<HealthBodyPage> {
  final List<BodyRecord> _records = <BodyRecord>[];
  BodyStats? _stats;

  /// 后端 500 无法读取的日期（二分降级的终点），用于提示与下次刷新时绕开。
  final Set<String> _skippedDates = <String>{};

  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 趋势图当前选中的点下标；null 表示未选中（显示操作提示）。
  int? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取统计，再按日期窗口取历史；统计失败按整体失败提示。
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
      _status = LoadStatus.loading;
      _message = null;
    });
    try {
      final Map<String, dynamic>? statsJson = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/body/stats',
                queryParameters: <String, dynamic>{'days': 0},
              ))
          .data;
      if (statsJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '体重统计返回数据为空',
        );
      }
      final BodyStats stats = BodyStats.fromJson(statsJson);
      final List<String> dates = <String>[
        for (final BodyTrendPoint point in stats.trend)
          if (point.date.isNotEmpty) point.date,
      ]..sort();
      final List<BodyRecord> records = <BodyRecord>[];
      if (dates.isNotEmpty) {
        await _fetchWindows(scope, dates, records);
      }
      records.sort((BodyRecord a, BodyRecord b) {
        final int byDate = b.recordDate.compareTo(a.recordDate);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = stats;
        _records
          ..clear()
          ..addAll(records);
        _status = LoadStatus.ready;
        // 趋势默认停在最后一个点（最新一天），与收益曲线默认指向最后一天一致。
        final int weightPoints = stats.trend
            .where((BodyTrendPoint point) => point.weightKg != null)
            .length;
        _selected = weightPoints > 0 ? weightPoints - 1 : null;
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

  /// 按已知坏日期把整体日期区间切成若干窗口，避免每次都从二分开始试探。
  Future<void> _fetchWindows(
    AppScope scope,
    List<String> dates,
    List<BodyRecord> output,
  ) async {
    String windowStart = dates.first;
    for (final String date in dates) {
      if (!_skippedDates.contains(date)) {
        continue;
      }
      // 坏日期之前的有效窗口先取。
      if (windowStart.compareTo(date) < 0) {
        await _fetchRange(scope, windowStart, _previousDay(date), dates, output);
      }
      windowStart = _nextDay(date);
    }
    if (windowStart.compareTo(dates.last) <= 0) {
      await _fetchRange(scope, windowStart, dates.last, dates, output);
    }
  }

  /// 取 `[start, end]` 窗口；500 时二分降级，直到只剩单日才记为不可读。
  Future<void> _fetchRange(
    AppScope scope,
    String start,
    String end,
    List<String> dates,
    List<BodyRecord> output, {
    int depth = 0,
  }) async {
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/body',
                  queryParameters: <String, dynamic>{
            'page': 1,
            'page_size': 100,
            'start': start,
            'end': end,
          }))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '体重记录返回数据为空',
        );
      }
      output.addAll(_parseRecords(json));
    } on ApiException catch (error) {
      if (error.kind != ApiErrorKind.server || depth >= 8) {
        rethrow;
      }
      final List<String> candidates = <String>[
        for (final String date in dates)
          if (date.compareTo(start) >= 0 && date.compareTo(end) <= 0) date,
      ];
      if (candidates.length <= 1) {
        _skippedDates.addAll(candidates);
        return;
      }
      // 取左偏中点：保证左右两段都至少落到一个已有日期上，不会原地递归。
      final int midIndex = (candidates.length - 1) ~/ 2;
      await _fetchRange(
          scope, start, candidates[midIndex], dates, output,
          depth: depth + 1);
      await _fetchRange(
          scope, candidates[midIndex + 1], end, dates, output,
          depth: depth + 1);
    }
  }

  /// `2026-06-12` → `2026-06-11`。
  String _previousDay(String date) {
    final DateTime? parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return date;
    }
    return _dateKey(parsed.subtract(const Duration(days: 1)));
  }

  /// `2026-06-12` → `2026-06-13`。
  String _nextDay(String date) {
    final DateTime? parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return date;
    }
    return _dateKey(parsed.add(const Duration(days: 1)));
  }

  /// `DateTime` → `yyyy-MM-dd`（后端 `start`/`end` 口径）。
  String _dateKey(DateTime date) {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  List<BodyRecord> _parseRecords(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => BodyRecord.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  /// 新增：表单返回 true 后刷新本页，并同步健康域总览（首页汇总口径）。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/health/body/new');
    if (created == true && mounted) {
      await _refresh();
      if (mounted) {
        AppScope.of(context).overview.refreshHealth();
      }
    }
  }

  /// 编辑：带上列表快照，断网也能打开预填。
  Future<void> _openEdit(BodyRecord record) async {
    final bool? changed =
        await context.push<bool>('/health/body/${record.id}', extra: record);
    if (changed == true && mounted) {
      await _refresh();
      if (mounted) {
        AppScope.of(context).overview.refreshHealth();
      }
    }
  }

  /// 蓝牙称重：同步成功后刷新列表与健康域总览。
  Future<void> _openBle() async {
    final bool? synced = await context.push<bool>('/health/body/ble');
    if (synced == true && mounted) {
      await _refresh();
      if (mounted) {
        AppScope.of(context).overview.refreshHealth();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailPageScaffold(
      title: '体重记录',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _status == LoadStatus.loading ? null : _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('新增体重'),
      ),
      child: ListView(
        // 底部预留悬浮「记录身体」按钮的安全距离。
        padding: const EdgeInsets.only(bottom: 120),
        children: <Widget>[
          ListStatusView(
            status: _status,
            message: _message,
            onRetry: _refresh,
          ),
          if (_status == LoadStatus.ready) ...<Widget>[
            _overviewCard(),
            _trendCard(),
            _historyCard(),
          ],
        ],
      ),
    );
  }

  /// 概览卡：2×2 指标，避免 4 列在 375dp / 1.3 倍字号下挤压。
  Widget _overviewCard() {
    final ThemeData theme = Theme.of(context);
    final BodyStats? stats = _stats;
    final BodyLatest? latest = stats?.latest;
    final String date = latest?.date ?? '';
    return SectionCard(
      title: '身体概览',
      trailing: Text(
        '共 ${stats?.recordCount ?? 0} 条',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: <Widget>[
          Row(
            spacing: 16,
            children: <Widget>[
              Expanded(
                child: MetricPlaceholder(
                  label: date.isEmpty ? '当前体重' : '当前体重 · ${_shortDate(date)}',
                  value: _weightText(latest?.weightKg),
                ),
              ),
              Expanded(
                child: MetricPlaceholder(
                  label: 'BMI',
                  value: _numberText(latest?.bmi, digits: 1),
                ),
              ),
            ],
          ),
          Row(
            spacing: 16,
            children: <Widget>[
              Expanded(
                child: MetricPlaceholder(
                  label: '体脂率',
                  value: _numberText(latest?.bodyFatPercent, digits: 1, unit: '%'),
                ),
              ),
              Expanded(
                child: MetricPlaceholder(
                  label: '平均体重',
                  value: _weightText(stats?.avgWeight),
                ),
              ),
            ],
          ),
          if (_rangeText(stats) != null)
            Text(
              _rangeText(stats)!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          // 蓝牙入口：与手动录入并存，失败时可从蓝牙页降级回手动录入。
          AppSecondaryButton(
            label: '蓝牙体重秤称重',
            icon: Icons.bluetooth_searching,
            onPressed: _status == LoadStatus.loading ? null : _openBle,
          ),
        ],
      ),
    );
  }

  /// 区间说明：最低/最高只有拿到 2 个不同测量值才有意义。
  String? _rangeText(BodyStats? stats) {
    final double? min = stats?.minWeight;
    final double? max = stats?.maxWeight;
    if (min == null || max == null) {
      return null;
    }
    return '区间最低 ${min.toStringAsFixed(1)} kg · 最高 ${max.toStringAsFixed(1)} kg';
  }

  /// 趋势卡：体重折线；记录日不足 2 个时给空态说明。
  Widget _trendCard() {
    final List<({String date, double weight})> points = _weightPoints();
    return SectionCard(
      title: '体重趋势',
      trailing: Text(
        '${points.length} 个体重点',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      child: points.length < 2
          ? const EmptyState(
              icon: Icons.monitor_weight_outlined,
              title: '数据不足，暂不画趋势',
              description: '至少 2 个记录日才有折线，继续记录后自动展示。',
              compact: true,
            )
          : _WeightChart(
              points: points,
              selected: _selected,
              onSelect: (int index) => setState(() => _selected = index),
            ),
    );
  }

  /// 历史卡：按日期倒序，行内展示体重与关键体成分，空值显示「—」。
  Widget _historyCard() {
    final ThemeData theme = Theme.of(context);
    final int total = _stats?.recordCount ?? _records.length;
    if (_records.isEmpty) {
      return SectionCard(
        title: '历史记录',
        child: const EmptyState(
          icon: Icons.monitor_weight_outlined,
          title: '暂无体重记录',
          description: '点右下「新增体重」录入第一条',
          compact: true,
        ),
      );
    }
    return SectionCard(
      title: '历史记录',
      trailing: Text(
        '共 $total 条',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: <Widget>[
          for (final BodyRecord record in _records)
            _BodyRow(record: record, onTap: () => _openEdit(record)),
          if (_skippedDates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                spacing: 6,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Text(
                      '${_skippedDates.length} 条历史记录（'
                      '${_skippedDates.join('、')}）因后端数据异常（身高/体重为 0）'
                      '暂无法读取，已记录待后端修复。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 趋势图的点：只取有体重的记录日，保持后端日期升序。
  List<({String date, double weight})> _weightPoints() {
    return <({String date, double weight})>[
      for (final BodyTrendPoint point in _stats?.trend ?? const <BodyTrendPoint>[])
        if (point.weightKg != null)
          (date: point.date, weight: point.weightKg!),
    ];
  }
}

/// 数值展示：null 与 0 都视为「未采集」，统一「—」。
String _numberText(double? value, {int digits = 1, String unit = ''}) {
  if (value == null || value == 0) {
    return '—';
  }
  return '${value.toStringAsFixed(digits)}$unit';
}

/// 体重展示：保留 1 位小数并带单位。
String _weightText(double? value) {
  if (value == null || value == 0) {
    return '—';
  }
  return '${value.toStringAsFixed(1)} kg';
}

/// `2026-10-30` → `10-30`。
String _shortDate(String date) =>
    date.length >= 10 ? date.substring(5) : date;

/// 计算 BMI（记录里缺失时按身高体重补算，与后端 `latest` 口径一致）。
double? _bmiOf(BodyRecord record) {
  if (record.bmi != null) {
    return record.bmi;
  }
  final double? height = record.heightCm;
  final double? weight = record.weightKg;
  if (height == null || weight == null) {
    return null;
  }
  final double meters = height / 100;
  return weight / (meters * meters);
}

/// 历史行：日期 + 体重，第二行用 Wrap 展示体成分，窄屏自动换行不溢出。
class _BodyRow extends StatelessWidget {
  const _BodyRow({required this.record, required this.onTap});

  final BodyRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? chip = theme.textTheme.bodySmall?.copyWith(color: muted);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    record.recordDate,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  _weightText(record.weightKg),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 18, color: muted),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                Text('BMI ${_numberText(_bmiOf(record), digits: 1)}', style: chip),
                Text(
                  '体脂 ${_numberText(record.bodyFatPercent, digits: 1, unit: '%')}',
                  style: chip,
                ),
                Text(
                  '肌肉 ${_numberText(record.musclePercent, digits: 1, unit: '%')}',
                  style: chip,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 体重折线：点按或长按横向拖动读取单点，交互与收益曲线一致。
class _WeightChart extends StatelessWidget {
  const _WeightChart({
    required this.points,
    required this.selected,
    required this.onSelect,
  });

  final List<({String date, double weight})> points;
  final int? selected;
  final ValueChanged<int> onSelect;

  static const double _chartHeight = 148;
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

  /// 横轴标签抽稀：按可用宽度取 2~4 个关键点，重复日期去重。
  List<String> _axisLabels(double width) {
    final int count = width >= 320 ? 4 : (width >= 220 ? 3 : 2);
    final List<String> labels = <String>[];
    for (int i = 0; i < count; i++) {
      final int index = ((points.length - 1) * i / (count - 1)).round();
      final int safe = index < 0
          ? 0
          : (index >= points.length ? points.length - 1 : index);
      final String label = _shortDate(points[safe].date);
      if (labels.isEmpty || labels.last != label) {
        labels.add(label);
      }
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final ({String date, double weight})? current =
        selected == null || selected! >= points.length ? null : points[selected!];
    final double minWeight = points
        .map((({String date, double weight}) point) => point.weight)
        .reduce((double a, double b) => a < b ? a : b);
    final double maxWeight = points
        .map((({String date, double weight}) point) => point.weight)
        .reduce((double a, double b) => a > b ? a : b);
    // 上下各留 0.5kg：数据全相同时折线落在中线而不是贴边。
    final double minimum = minWeight - 0.5;
    final double maximum = maxWeight + 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Text(
          current == null
              ? '点按或长按曲线查看单日体重'
              : '${current.date} · ${current.weight.toStringAsFixed(1)} kg',
          style: current == null
              ? theme.textTheme.bodySmall?.copyWith(color: muted)
              : theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
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
                  label: '体重曲线，点按或长按拖动查看单日体重',
                  child: CustomPaint(
                    size: Size(width, _chartHeight),
                    painter: _WeightCurvePainter(
                      values: points
                          .map((({String date, double weight}) point) =>
                              point.weight)
                          .toList(),
                      lineColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      gridColor: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                      minimum: minimum,
                      maximum: maximum,
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
          '按记录日连线，纵轴为体重（kg）；按住曲线横向拖动可逐日查看。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// 折线绘制：浅色网格 + 折线 + 选中点竖虚线/实心圆点。
class _WeightCurvePainter extends CustomPainter {
  _WeightCurvePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.minimum,
    required this.maximum,
    this.selectedIndex,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;
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
    const double top = 8;
    const double bottom = 8;
    final double usableWidth = size.width - left - right;
    final double usableHeight = size.height - top - bottom;
    final double span = maximum - minimum;

    double yOf(double value) {
      if (span == 0) {
        return top + usableHeight / 2;
      }
      return top + usableHeight * (1 - (value - minimum) / span);
    }

    double xOf(int index) =>
        left + usableWidth * index / (values.length - 1);

    // 三条水平参考线：最高 / 中位 / 最低。
    final Paint grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final double ratio in <double>[0, 0.5, 1]) {
      final double y = top + usableHeight * ratio;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
    }

    final Path path = Path()..moveTo(xOf(0), yOf(values.first));
    for (int i = 1; i < values.length; i++) {
      path.lineTo(xOf(i), yOf(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    final int? index = selectedIndex;
    if (index == null || index < 0 || index >= values.length) {
      return;
    }
    final double x = xOf(index);
    final double y = yOf(values[index]);
    final Paint dash = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (double dy = top; dy < size.height - bottom; dy += 8) {
      canvas.drawLine(Offset(x, dy), Offset(x, dy + 4), dash);
    }
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_WeightCurvePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.minimum != minimum ||
        oldDelegate.maximum != maximum ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
