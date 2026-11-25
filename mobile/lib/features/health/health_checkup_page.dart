import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_status.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';

/// 体检指标：概览 + 异常/未判定/正常分组 + 指标历史展开 + 记录增改删。
///
/// 数据：
/// - `GET /health/checkup/stats?days=0`（概览与分组）
/// - `GET /health/checkup?page=1&page_size=100`（可编辑的记录明细）
/// - 写操作在体检表单页：POST / PUT / DELETE。
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

  /// 可编辑的记录明细（与统计接口分开取，写操作后一并刷新）。
  final List<CheckupRecord> _records = <CheckupRecord>[];
  int _recordsTotal = 0;

  /// 当前展开历史的指标名；同一时间只展开一项，一屏最多一张折线。
  String? _expandedItem;

  /// 正常指标组默认收起，避免一屏几十条。
  bool _showNormal = false;

  /// 当前栏目：0 = 记录，1 = 面板，2 = 模板。
  int _tab = 0;

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
      final List<Map<String, dynamic>?> responses = await Future.wait(
        <Future<Map<String, dynamic>?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/checkup/stats',
                queryParameters: <String, dynamic>{'days': 0},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/checkup',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? json = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (json == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '体检接口返回数据为空',
        );
      }
      final List<CheckupRecord> records =
          ((listJson['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (Map item) =>
                    CheckupRecord.fromJson(item.cast<String, dynamic>()),
              )
              .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = CheckupStats.fromJson(json);
        _records
          ..clear()
          ..addAll(records);
        _recordsTotal = (listJson['total'] as num?)?.toInt() ?? records.length;
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final bool offline =
          scope.auth.hasLocalSession &&
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

  /// 打开体检表单：`record` 为空是新增，否则带快照预填编辑。
  ///
  /// 表单保存/删除成功后返回 true，本页重拉统计与记录明细。
  Future<void> _openForm([CheckupRecord? record]) async {
    final String path = record == null
        ? '/health/checkup/new'
        : '/health/checkup/${record.id}';
    final bool? changed = await context.push<bool>(path, extra: record);
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final CheckupStats? stats = _stats;
    // 新增记录与模板入口都留在页面内：内嵌到健康根页时导航栏操作会被隐藏。
    return DetailPageScaffold(
      title: '体检指标',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (stats == null)
            Expanded(
              child: ListPageBody(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            )
          else ...<Widget>[
            // 刷新失败但仍有旧数据：保留内容，顶部提示可重试。
            if (_status != LoadStatus.ready && _status != LoadStatus.idle)
              OverviewStatusBanner(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            SummaryStrip(
              caption: _overviewCaption(stats),
              items: _summaryItems(stats),
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '记录', value: 0),
                V2SegmentedOption<int>(label: '面板', value: 1),
                V2SegmentedOption<int>(label: '模板', value: 2),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _recordsTab(stats),
                  _itemsTab(stats),
                  _templatesTab(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 概览句：指标项数与偏高 / 偏低 / 正常分布。
  String _overviewCaption(CheckupStats stats) {
    final String high = stats.statusLabel['high'] ?? '偏高';
    final String low = stats.statusLabel['low'] ?? '偏低';
    final String normal = stats.statusLabel['normal'] ?? '正常';
    return '共 ${formatInt(stats.items.length)} 项指标 · '
        '$high ${formatInt(stats.highCount)} · '
        '$low ${formatInt(stats.lowCount)} · '
        '$normal ${formatInt(stats.normalCount)}';
  }

  /// 概览指标轨：指标总数 / 异常指标 / 检查记录，异常项数为正时用警示色。
  List<StatRailItem> _summaryItems(CheckupStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    return <StatRailItem>[
      StatRailItem(
        label: '指标总数',
        value: formatInt(stats.items.length),
        unit: '项',
      ),
      StatRailItem(
        label: '异常指标',
        value: formatInt(stats.abnormalCount),
        unit: '项',
        color: stats.abnormalCount > 0 ? tokens.red : null,
      ),
      StatRailItem(
        label: '检查记录',
        value: formatInt(stats.totalCount),
        unit: '条',
      ),
    ];
  }

  /// 记录栏目：可编辑的检查记录列表，新增入口在标题右侧。
  Widget _recordsTab(CheckupStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    return ListPageBody(
      // 数据状态已由外层统一处理，栏目内始终渲染已就绪的内容。
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '检查记录 · 共 ${formatInt(_recordsTotal)} 条',
          actionLabel: '新增记录',
          onAction: () => _openForm(),
        ),
        GroupCard(
          children: <Widget>[
            if (_records.isEmpty)
              const EmptyState(
                icon: Icons.monitor_heart_outlined,
                title: '暂无检查记录',
                description: '点「新增记录」录入第一条',
                compact: true,
              )
            else
              for (final CheckupRecord record in _records)
                _CheckupRecordRow(
                  record: record,
                  statusLabel: _recordStatusLabel(stats, record.result),
                  onTap: () => _openForm(record),
                ),
          ],
        ),
        if (_recordsTotal > _records.length)
          Text(
            '接口仅返回最近 ${formatInt(_records.length)} 条，更早记录请在网页端查看。',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
        Text(
          '记录与网页端同源；点按记录进入编辑，可修改或删除。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
      footer: _records.isEmpty
          ? null
          : ListLoadMoreFooter(
              loading: false,
              hasMore: false,
              onPressed: () {},
            ),
    );
  }

  /// 面板栏目：异常 / 未判定 / 正常三组指标，点按展开单项历史。
  Widget _itemsTab(CheckupStats stats) {
    final AppTokens tokens = AppTokens.of(context);
    final List<CheckupItem> abnormal = _abnormalItems(stats);
    final List<CheckupItem> unknown = _unknownItems(stats);
    final List<CheckupItem> normal = _normalItems(stats);
    final TextStyle metaStyle = AppType.rowMeta.copyWith(color: tokens.text2);
    return ListPageBody(
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        if (stats.items.isEmpty) ...<Widget>[
          const SectionHeader(title: '体检指标'),
          const GroupCard(
            children: <Widget>[
              EmptyState(
                icon: Icons.monitor_heart_outlined,
                title: '暂无体检指标',
                description: '还没有体检指标记录',
                compact: true,
              ),
            ],
          ),
        ] else ...<Widget>[
          SectionHeader(title: '异常指标 · ${formatInt(abnormal.length)} 项'),
          GroupCard(
            children: abnormal.isEmpty
                ? <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text('当前所有指标均在参考范围内', style: metaStyle),
                    ),
                  ]
                : <Widget>[
                    for (final CheckupItem item in abnormal)
                      _CheckupRow(
                        item: item,
                        expanded: _expandedItem == item.itemName,
                        statusLabel: _statusLabel(stats, item),
                        onTap: () => _toggleItem(item.itemName),
                      ),
                  ],
          ),
          if (unknown.isNotEmpty) ...<Widget>[
            SectionHeader(title: '未判定指标 · ${formatInt(unknown.length)} 项'),
            GroupCard(
              children: <Widget>[
                for (final CheckupItem item in unknown)
                  _CheckupRow(
                    item: item,
                    expanded: _expandedItem == item.itemName,
                    statusLabel: _statusLabel(stats, item),
                    onTap: () => _toggleItem(item.itemName),
                  ),
              ],
            ),
          ],
          SectionHeader(
            title: '正常指标 · ${formatInt(normal.length)} 项',
            actionLabel: _showNormal ? '收起' : '展开',
            onAction: () => setState(() => _showNormal = !_showNormal),
          ),
          GroupCard(
            children: _showNormal
                ? <Widget>[
                    for (final CheckupItem item in normal)
                      _CheckupRow(
                        item: item,
                        expanded: _expandedItem == item.itemName,
                        statusLabel: _statusLabel(stats, item),
                        onTap: () => _toggleItem(item.itemName),
                      ),
                  ]
                : <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text(
                        '已收起 ${formatInt(normal.length)} 项，点右上角「展开」查看',
                        style: metaStyle,
                      ),
                    ),
                  ],
          ),
        ],
        Text(
          '仅偏高 / 偏低使用警示色，正常与未判定保持中性。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 模板栏目：单指标模板与组合套餐维护入口。
  Widget _templatesTab() {
    final AppTokens tokens = AppTokens.of(context);
    return ListPageBody(
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '模板与组合',
          actionLabel: '打开',
          onAction: _openTemplates,
        ),
        GroupCard(
          children: <Widget>[
            V2EntryRow(
              title: '单指标模板与组合套餐',
              subtitle: '维护模板与组合，录入时一键带入',
              icon: Icons.dashboard_customize_outlined,
              onTap: _openTemplates,
            ),
          ],
        ),
        Text(
          '模板与组合与网页端共用同一份数据；改动后回到「记录」新增即可选用。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 打开模板与组合页（原导航栏入口，内嵌模式下移到页面内）。
  void _openTemplates() {
    context.push<void>('/health/checkup/templates');
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
      .where(
        (CheckupItem item) =>
            item.latestResult == null || item.latestResult == 'unknown',
      )
      .toList();
}

/// 正常指标，按名称排序。
List<CheckupItem> _normalItems(CheckupStats stats) {
  final List<CheckupItem> items = stats.items
      .where((CheckupItem item) => item.latestResult == 'normal')
      .toList();
  items.sort(
    (CheckupItem a, CheckupItem b) => a.itemName.compareTo(b.itemName),
  );
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

/// 单条记录的状态文案：没有状态时按「未判定」展示，不臆造正常/异常。
String _recordStatusLabel(CheckupStats stats, String? result) {
  if (result == null || result.isEmpty) {
    return '未判定';
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

/// 单条检查记录行：指标项 + 日期 / 参考范围 → 数值、单位与状态；点击编辑。
class _CheckupRecordRow extends StatelessWidget {
  const _CheckupRecordRow({
    required this.record,
    required this.statusLabel,
    required this.onTap,
  });

  final CheckupRecord record;
  final String statusLabel;
  final VoidCallback onTap;

  /// 参考范围：后端原值优先展示，缺失时才由上下限拼出。
  ///
  /// 后端历史数据的区间小数位不统一（`65.00-85.00` 与 `208.3-428.4`），
  /// 这里统一去掉无意义的尾随零，保证同一页内区间格式一致。
  String get _reference {
    final String? raw = record.referenceRange?.trim();
    if (raw != null && raw.isNotEmpty) {
      return _trimReference(raw);
    }
    final double? low = record.refLow;
    final double? high = record.refHigh;
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

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String unit = (record.unit ?? '').trim();
    final Color valueColor = _valueColor(context, record.result) ?? tokens.text;
    final String number = _metricValue(record.value);
    // 长单位单独占一行，避免在中途按字符折断（如 mL/(min*1.73m²)）。
    final bool longUnit = unit.length > 8;
    final String value = unit.isEmpty
        ? number
        : (longUnit ? '$number\n$unit' : '$number $unit');
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
              // 状态徽标紧跟指标名，不再压在数值下方：所有行都保持
              // 「标题 + 数值 / 说明」两行节奏，列表不会高低错落。
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      record.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(result: record.result, label: statusLabel),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 15, color: tokens.text3),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${formatListDate(record.checkDate)} · 参考 $_reference',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      // 长单位已用换行符分成两行，这里最多两行。
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppType.rowValue.copyWith(color: valueColor),
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
    final AppTokens tokens = AppTokens.of(context);
    final Color? valueColor = _valueColor(context, item.latestResult);
    final String unit = (item.unit ?? '').trim();
    final String number = _metricValue(item.latestValue);
    final bool longUnit = unit.length > 8;
    final String latest = unit.isEmpty
        ? number
        : (longUnit ? '$number\n$unit' : '$number $unit');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: <Widget>[
            // 与「记录」栏同一两行节奏：标题 + 状态在上，说明 + 数值在下。
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowTitle.copyWith(color: tokens.text),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(result: item.latestResult, label: statusLabel),
                const SizedBox(width: 2),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: tokens.text3,
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '参考 ${_referenceText(item)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    latest,
                    // 与记录行一致：长单位折两行，不裁掉单位。
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppType.rowValue.copyWith(
                      color: valueColor ?? tokens.text,
                    ),
                  ),
                ),
              ],
            ),
            if (expanded) _CheckupHistory(item: item, valueColor: valueColor),
          ],
        ),
      ),
    );
  }
}

/// 状态徽标：偏高红、偏低橙，正常与未判定保持中性灰。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.result, required this.label});

  final String? result;
  final String label;

  @override
  Widget build(BuildContext context) {
    final V2BadgeTone tone = switch (result) {
      'high' => V2BadgeTone.danger,
      'low' => V2BadgeTone.warn,
      _ => V2BadgeTone.gray,
    };
    return V2Badge(label, tone: tone);
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
  const _CheckupHistory({required this.item, required this.valueColor});

  final CheckupItem item;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Color muted = tokens.text2;
    final int shown = item.trend.length;
    final List<double> chartValues = item.trend
        .where((CheckupTrendPoint point) => point.value != null)
        .map((CheckupTrendPoint point) => point.value!)
        .toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: tokens.fill2,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
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
                  style: AppType.section.copyWith(color: muted),
                ),
              ),
              Text(
                item.count > shown
                    ? '共 ${item.count} 次 · 最近 $shown 次'
                    : '共 ${item.count} 次',
                style: AppType.rowMeta.copyWith(color: tokens.text3),
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
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ],
          if (shown == 0)
            Text(
              '无历史明细',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            )
          else
            for (final CheckupTrendPoint point in item.trend.reversed)
              Row(
                spacing: 12,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      formatListDate(point.date),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: muted),
                    ),
                  ),
                  Text(
                    _metricValue(point.value),
                    style: AppType.rowMeta.copyWith(
                      color: _valueColor(context, point.result),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  Text(
                    _pointLabel(point.result),
                    style: AppType.rowMeta.copyWith(color: tokens.text3),
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
