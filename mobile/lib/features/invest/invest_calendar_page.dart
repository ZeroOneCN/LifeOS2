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

/// 交易日历：月份切换 + 月汇总 + 日历网格（每日盈亏）/ 每日明细。
///
/// 数据来源（与网页端 `pages/investment/forex.tsx` 的交易日历一致）：
/// - `GET /investment/forex/calendar?month=YYYY-MM`。
///
/// 颜色口径：盈利绿、亏损红、无交易中性；负数一律红、正数一律绿。
/// 月份与「日历 / 明细」都在页内用分段控件就地切换，不跳转路由。
class InvestCalendarPage extends StatefulWidget {
  const InvestCalendarPage({super.key});

  @override
  State<InvestCalendarPage> createState() => _InvestCalendarPageState();
}

class _InvestCalendarPageState extends State<InvestCalendarPage> {
  // 当前展示月份（固定为当月 1 号，便于切换）。
  late DateTime _month;
  ForexCalendar? _calendar;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 选中日期（用于日历下方明细）；切换月份后清空。
  int? _selectedDay;

  /// 当前栏目：0 日历、1 明细。
  int _tab = 0;

  /// 明细区域 key：选中日期后用它把明细滚动到可视区。
  final GlobalKey _detailKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _month = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取当前月份日历；切换月份保留旧数据避免闪空。
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
      _status = _calendar == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/investment/forex/calendar',
                queryParameters: <String, dynamic>{'month': _monthKey(_month)},
              ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '日历接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _calendar = ForexCalendar.fromJson(json);
        _status = LoadStatus.ready;
        _selectedDay = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _calendar == null ? _errorStatus(scope, error) : LoadStatus.ready;
        _message = error.message;
      });
      if (_calendar != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('日历刷新失败：${error.message}')),
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

  /// `YYYY-MM` 请求参数。
  String _monthKey(DateTime month) => '${month.year}-${_two(month.month)}';

  /// 按月切换；不限制未来月份（与网页端一致，空月显示无交易）。
  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
    });
    _refresh();
  }

  /// 回到本月。
  void _goCurrentMonth() {
    final DateTime now = DateTime.now();
    final DateTime current = DateTime(now.year, now.month);
    if (current.year == _month.year && current.month == _month.month) {
      return;
    }
    setState(() {
      _month = current;
      _selectedDay = null;
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ForexCalendar? calendar = _calendar;
    final bool ready = _status == LoadStatus.ready || _status == LoadStatus.idle;

    return DetailPageScaffold(
      title: '交易日历',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (!ready || calendar == null)
            Expanded(
              child: ListPageBody(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            )
          else ...<Widget>[
            SummaryStrip(
              caption: _monthCaption(calendar),
              items: _summaryItems(calendar),
            ),
            // 月份分段：上一月 / 当前展示月 / 下一月，点两侧就地按月切换。
            V2Segmented<int>(
              options: _monthOptions,
              selected: 0,
              compact: true,
              onChanged: (int delta) {
                if (delta != 0) {
                  _shiftMonth(delta);
                }
              },
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '日历', value: 0),
                V2SegmentedOption<int>(label: '明细', value: 1),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _calendarTab(calendar),
                  _daysTab(calendar),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 月份分段选项：以当前展示月居中，左右各一个月，标签精确到年。
  List<V2SegmentedOption<int>> get _monthOptions {
    final DateTime prev = DateTime(_month.year, _month.month - 1);
    final DateTime next = DateTime(_month.year, _month.month + 1);
    return <V2SegmentedOption<int>>[
      V2SegmentedOption<int>(label: _monthLabel(prev), value: -1),
      V2SegmentedOption<int>(label: _monthLabel(_month), value: 0),
      V2SegmentedOption<int>(label: _monthLabel(next), value: 1),
    ];
  }

  /// 月份标签：`11月`（年份在概览句里给出，避免窄屏格子被截断）。
  String _monthLabel(DateTime month) => '${month.month}月';

  /// 概览句：年月 + 盈利 / 亏损天数。
  String _monthCaption(ForexCalendar calendar) {
    final ForexCalendarSummary summary = calendar.summary;
    return '${calendar.year} 年 ${calendar.month} 月 · '
        '盈利 ${formatInt(summary.winDays)} 天 · '
        '亏损 ${formatInt(summary.lossDays)} 天';
  }

  /// 概览指标轨：月盈亏 / 月收益率 / 交易日。
  List<StatRailItem> _summaryItems(ForexCalendar calendar) {
    final ForexCalendarSummary summary = calendar.summary;
    // 本月没有任何交易日时，盈亏与收益率按空值展示，不冒充 $0.00 / 0.0%。
    final bool empty = summary.tradingDays == 0;
    return <StatRailItem>[
      StatRailItem(
        label: '月盈亏',
        value: empty ? '—' : _usdCompact(summary.monthPnl, signed: true),
        color: empty ? null : _pnlColor(summary.monthPnl),
      ),
      StatRailItem(
        label: '月收益率',
        value: empty ? '—' : formatPercent(summary.returnRate),
        color: empty ? null : _pnlColor(summary.returnRate),
      ),
      StatRailItem(
        label: '交易日',
        value: formatInt(summary.tradingDays),
        unit: '天',
      ),
    ];
  }

  /// 盈亏分色：正 success、负 danger、0 保持中性。
  Color? _pnlColor(double value) {
    final AppSemanticColors colors = context.semanticColors;
    if (value > 0) {
      return colors.success;
    }
    if (value < 0) {
      return colors.danger;
    }
    return null;
  }

  /// 日历栏目：日历网格 + 图例 + 选中日明细。
  Widget _calendarTab(ForexCalendar calendar) {
    final AppTokens tokens = AppTokens.of(context);
    final int activeDays = calendar.days
        .where((ForexCalendarDay day) => day.active)
        .length;
    final bool isCurrentMonth = _isCurrentMonth();
    return ListPageBody(
      // 数据状态由外层统一处理，栏目内始终渲染已就绪的内容。
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '每日盈亏 · ${formatInt(activeDays)} 天交易',
          actionLabel: isCurrentMonth ? null : '回到本月',
          onAction: isCurrentMonth ? null : _goCurrentMonth,
        ),
        GroupCard(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: <Widget>[
                  // 空月也渲染完整日历：日期格结构一致，点任意一天可看到
                  // 「当日无交易」，不会因为某月没交易就丢掉整块日历。
                  if (activeDays == 0)
                    Text(
                      '本月没有交易记录，可用上方月份切换查看其他月份。',
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  _CalendarGrid(
                    year: calendar.year,
                    month: calendar.month,
                    days: calendar.days,
                    selectedDay: _selectedDay,
                    onSelect: _selectDay,
                  ),
                  const _Legend(),
                  if (_selectedDay != null)
                    _DayDetail(
                      // 选中后把明细滚进可视区，避免在 375dp 上点完日期
                      // 还要手动下滑才知道明细出现在哪儿。
                      key: _detailKey,
                      day: calendar.days.firstWhere(
                        (ForexCalendarDay day) => day.day == _selectedDay,
                      ),
                      year: calendar.year,
                      month: calendar.month,
                    ),
                ],
              ),
            ),
          ],
        ),
        Text(
          '点日期查看当日明细；盈利绿、亏损红、无交易中性。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 明细栏目：当月有交易的日期逐条列出，点按回到日历并定位当天。
  Widget _daysTab(ForexCalendar calendar) {
    final AppTokens tokens = AppTokens.of(context);
    final List<ForexCalendarDay> active = calendar.days
        .where((ForexCalendarDay day) => day.active)
        .toList(growable: false);
    return ListPageBody(
      status: LoadStatus.ready,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(title: '每日明细 · ${formatInt(active.length)} 天'),
        GroupCard(
          children: active.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: '本月没有交易记录',
                    description: '可用上方月份切换查看其他月份',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final ForexCalendarDay day in active)
                    _DayRow(
                      day: day,
                      month: calendar.month,
                      onTap: () => _showDay(day.day),
                    ),
                ],
        ),
        Text(
          '仅列出有交易的日期；金额为当日已平仓交易的净额。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 从「明细」点某一天：切回「日历」并选中该日。
  void _showDay(int day) {
    setState(() {
      _tab = 0;
      _selectedDay = day;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? detail = _detailKey.currentContext;
      if (detail == null) {
        return;
      }
      Scrollable.ensureVisible(
        detail,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        // 0.9 让明细底部贴近可视区下沿、上方留一点上下文（日历最后一行）。
        alignment: 0.9,
      );
    });
  }

  /// 点选 / 取消某一天；选中后把明细滚动到可视区内。
  void _selectDay(int day) {
    final bool deselect = _selectedDay == day;
    setState(() => _selectedDay = deselect ? null : day);
    if (deselect) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? detail = _detailKey.currentContext;
      if (detail == null) {
        return;
      }
      Scrollable.ensureVisible(
        detail,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.9,
      );
    });
  }

  /// 当前展示的是否为本月。
  bool _isCurrentMonth() {
    final DateTime now = DateTime.now();
    return now.year == _month.year && now.month == _month.month;
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

/// 单日明细行：日期 + 盈亏徽标在上，笔数说明 + 当日盈亏在下。
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.month,
    required this.onTap,
  });

  final ForexCalendarDay day;
  final int month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final Color pnlColor = day.pnl > 0
        ? colors.success
        : (day.pnl < 0 ? colors.danger : tokens.text2);
    final V2BadgeTone tone = day.pnl > 0
        ? V2BadgeTone.green
        : (day.pnl < 0 ? V2BadgeTone.danger : V2BadgeTone.gray);
    final String badge = day.pnl > 0 ? '盈利' : (day.pnl < 0 ? '亏损' : '持平');
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
              // 徽标跟随日期放在上一行，金额固定在下一行右侧，行高保持齐整。
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '$month月${day.day}日',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  V2Badge(badge, tone: tone),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 15, color: tokens.text3),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '交易 ${formatInt(day.count)} 笔 · '
                      '盈 ${formatInt(day.win)} · 亏 ${formatInt(day.loss)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatUsdSigned(day.pnl),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(color: pnlColor),
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

/// 日历网格：周一起始，7 列；有交易的日子按盈亏着色并显示金额。
class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.year,
    required this.month,
    required this.days,
    required this.selectedDay,
    required this.onSelect,
  });

  final int year;
  final int month;
  final List<ForexCalendarDay> days;
  final int? selectedDay;
  final ValueChanged<int> onSelect;

  static const List<String> _weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final Map<int, ForexCalendarDay> byDay = <int, ForexCalendarDay>{
      for (final ForexCalendarDay day in days) day.day: day,
    };
    // DateTime.weekday：周一 = 1，因此前置空格为 weekday - 1。
    final int leading = DateTime(year, month, 1).weekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String label in _weekdays)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = 4;
            final double cellWidth = (constraints.maxWidth - gap * 6) / 7;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (int i = 0; i < leading; i++)
                  SizedBox(width: cellWidth, height: 52),
                for (int day = 1; day <= _daysInMonth(year, month); day++)
                  SizedBox(
                    width: cellWidth,
                    height: 52,
                    child: _DayCell(
                      day: day,
                      data: byDay[day],
                      selected: selectedDay == day,
                      onTap: () => onSelect(day),
                      success: colors.success,
                      danger: colors.danger,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 当月天数。
  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;
}

/// 单日格子：日期数字 + 盈亏金额；无交易日只有数字。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.data,
    required this.selected,
    required this.onTap,
    required this.success,
    required this.danger,
  });

  final int day;
  final ForexCalendarDay? data;
  final bool selected;
  final VoidCallback onTap;
  final Color success;
  final Color danger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ForexCalendarDay? item = data;
    final bool active = item?.active ?? false;
    final double pnl = item?.pnl ?? 0;
    final Color fg = !active
        ? theme.colorScheme.onSurfaceVariant
        : (pnl > 0 ? success : (pnl < 0 ? danger : theme.colorScheme.onSurfaceVariant));
    final Color bg = !active
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : (pnl > 0
            ? success.withValues(alpha: 0.14)
            : (pnl < 0
                ? danger.withValues(alpha: 0.14)
                : theme.colorScheme.surfaceContainerHighest));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '$day',
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                color: active
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (active)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _compactPnl(pnl),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 格子内盈亏压缩：千位以上用 k；小数只在需要时保留一位。
  ///
  /// 之前按金额大小切换 0/1 位小数，导致同月格子出现「-164 / +13.0」；
  /// 现在统一规则：整数不带 `.0`，非整数保留一位。
  static String _compactPnl(double value) {
    final double abs = value.abs();
    final String sign = value < 0 ? '-' : '+';
    final String text = (abs >= 1000 ? abs / 1000 : abs).toStringAsFixed(1);
    final String trimmed =
        text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    return '$sign$trimmed${abs >= 1000 ? 'k' : ''}';
  }
}

/// 颜色图例。
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    Widget dot(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Text(
            label,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: <Widget>[
        dot(colors.success, '盈利'),
        dot(colors.danger, '亏损'),
        dot(theme.colorScheme.surfaceContainerHighest, '无交易'),
      ],
    );
  }
}

/// 选中日期的明细：交易笔数、盈/亏笔数、当日盈亏。
class _DayDetail extends StatelessWidget {
  const _DayDetail({
    super.key,
    required this.day,
    required this.year,
    required this.month,
  });

  final ForexCalendarDay day;
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    final Color pnlColor = day.pnl > 0
        ? colors.success
        : (day.pnl < 0 ? colors.danger : theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: <Widget>[
          Text(
            '$year-${_two(month)}-${_two(day.day)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          // 无交易日不显示 0 笔 / $0.00，直接说明当天没有交易。
          if (!day.active)
            Text(
              '当日无交易',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...<Widget>[
            Text(
              '交易 ${day.count} 笔 · 盈利 ${day.win} 笔 · 亏损 ${day.loss} 笔',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '当日盈亏 ${formatUsdSigned(day.pnl)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: pnlColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 两位补零。
String _two(int value) => value < 10 ? '0$value' : '$value';
