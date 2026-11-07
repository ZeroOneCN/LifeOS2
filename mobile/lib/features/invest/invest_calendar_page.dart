import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';

/// 交易日历：月份切换 + 月汇总 + 日历网格（每日盈亏）。
///
/// 数据来源（与网页端 `pages/investment/forex.tsx` 的交易日历一致）：
/// - `GET /investment/forex/calendar?month=YYYY-MM`。
///
/// 颜色口径：盈利绿、亏损红、无交易中性；负数一律红、正数一律绿。
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

  /// 选中日期（用于下方明细）；切换月份后清空。
  int? _selectedDay;

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
  String _monthKey(DateTime month) =>
      '${month.year}-${_two(month.month)}';

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
    final ThemeData theme = Theme.of(context);
    final ForexCalendar? calendar = _calendar;
    final bool isCurrentMonth = _isCurrentMonth();

    return DetailPageScaffold(
      title: '交易日历',
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
              // 时间控件紧贴标题下方：左移一月 / 当前月份 / 右移一月。
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(
                          '${_month.year} 年 ${_month.month} 月',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isCurrentMonth)
                          TextButton(
                            onPressed: _goCurrentMonth,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('回到本月', maxLines: 1),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              if (_status == LoadStatus.ready && calendar != null) ...<Widget>[
                SectionCard(
                  title: '本月汇总',
                  child: _MonthSummary(summary: calendar.summary),
                ),
                SectionCard(
                  title: '每日盈亏',
                  trailing: Text(
                    calendar.days.where((ForexCalendarDay d) => d.active).isEmpty
                        ? '本月无交易'
                        : '点日期看明细',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: <Widget>[
                      if (calendar.days.every(
                        (ForexCalendarDay d) => !d.active,
                      ))
                        Text(
                          '本月没有交易记录，可用上方箭头切换到有交易的月份。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        _CalendarGrid(
                          year: calendar.year,
                          month: calendar.month,
                          days: calendar.days,
                          selectedDay: _selectedDay,
                          onSelect: (int day) => setState(() {
                            _selectedDay = _selectedDay == day ? null : day;
                          }),
                        ),
                      _Legend(),
                      if (_selectedDay != null)
                        _DayDetail(
                          day: calendar.days.firstWhere(
                            (ForexCalendarDay d) => d.day == _selectedDay,
                          ),
                          year: calendar.year,
                          month: calendar.month,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 当前展示的是否为本月。
  bool _isCurrentMonth() {
    final DateTime now = DateTime.now();
    return now.year == _month.year && now.month == _month.month;
  }
}

/// 月汇总：月盈亏 / 交易日 / 盈利天 / 亏损天 / 月收益率。
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.summary});

  final ForexCalendarSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSemanticColors colors = context.semanticColors;
    // 本月没有任何交易日时，盈亏与收益率按空值展示，不冒充 $0.00 / 0.0%。
    final bool empty = summary.tradingDays == 0;
    final Color pnlColor = summary.monthPnl > 0
        ? colors.success
        : (summary.monthPnl < 0 ? colors.danger : theme.colorScheme.onSurfaceVariant);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final List<({String label, String value, Color color})> items =
        <({String label, String value, Color color})>[
          (
            label: '月盈亏',
            value: empty ? '—' : formatUsdSigned(summary.monthPnl),
            color: empty ? muted : pnlColor,
          ),
          (
            label: '月收益率',
            value: empty ? '—' : formatPercent(summary.returnRate),
            color: empty
                ? muted
                : (summary.returnRate > 0
                    ? colors.success
                    : (summary.returnRate < 0
                        ? colors.danger
                        : theme.colorScheme.onSurfaceVariant)),
          ),
          (
            label: '交易日',
            value: '${summary.tradingDays} 天',
            color: theme.colorScheme.onSurface,
          ),
          (
            label: '盈利天',
            value: '${summary.winDays} 天',
            color: empty ? muted : colors.success,
          ),
          (
            label: '亏损天',
            value: '${summary.lossDays} 天',
            color: empty ? muted : colors.danger,
          ),
        ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 8;
        final double width = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final ({String label, String value, Color color}) item
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
                        style: theme.textTheme.titleSmall?.copyWith(
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

  /// 格子内盈亏压缩：千位以上用 k，保留一位小数。
  static String _compactPnl(double value) {
    final double abs = value.abs();
    if (abs >= 1000) {
      return '${value < 0 ? '-' : '+'}${(abs / 1000).toStringAsFixed(1)}k';
    }
    return '${value < 0 ? '-' : '+'}${abs.toStringAsFixed(abs >= 100 ? 0 : 1)}';
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
