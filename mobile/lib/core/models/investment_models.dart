/// 投资域模型：外汇交易记录、交易资金记录（入金 / 出金 / 体验金）。
///
/// 字段口径与网页端 `pages/investment/forex.tsx` 一致：
/// - 列表来自 `GET /investment/forex?page=&page_size=`；
/// - 资金合计来自 `GET /investment/funds/stats`；
/// - 资金明细来自 `GET /investment/funds?page=&page_size=`。
library;

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

int _toInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

String _two(int value) => value < 10 ? '0$value' : '$value';

/// 资金类型标签：deposit 入金 / withdraw 出金 / experience 体验金。
String fundTypeLabel(String type) {
  switch (type) {
    case 'deposit':
      return '入金';
    case 'withdraw':
      return '出金';
    case 'experience':
      return '体验金';
    default:
      return type;
  }
}

/// 单条资金记录（`GET /investment/funds` 列表项）。
class FundRecord {
  const FundRecord({
    required this.id,
    required this.recordType,
    required this.amount,
    required this.recordDate,
    this.note,
  });

  final int id;
  final String recordType;
  final double amount;
  final String recordDate;
  final String? note;

  /// 类型文案。
  String get typeLabel => fundTypeLabel(recordType);

  /// 单号：`#id · 备注`，与网页端口径一致；备注为空时只留 `#id`。
  String get orderNo {
    final String? text = note?.trim();
    return (text == null || text.isEmpty) ? '#$id' : '#$id · $text';
  }

  factory FundRecord.fromJson(Map<String, dynamic> json) {
    return FundRecord(
      id: _toInt(json['id']),
      recordType: json['record_type'] as String? ?? '',
      amount: _toDouble(json['amount']),
      recordDate: json['record_date'] as String? ?? '',
      note: json['note'] as String?,
    );
  }
}

/// 资金合计（`GET /investment/funds/stats`）。
///
/// `net = 入金 - 出金 + 体验金`，与网页端四卡「净投入」同口径。
class FundStats {
  const FundStats({
    required this.deposit,
    required this.withdraw,
    required this.experience,
    required this.net,
    this.byDate = const <FundDayStat>[],
  });

  final double deposit;
  final double withdraw;
  final double experience;
  final double net;

  /// 按发生日期聚合（`by_date`，升序），供三色柱图使用。
  final List<FundDayStat> byDate;

  factory FundStats.fromJson(Map<String, dynamic> json) {
    return FundStats(
      deposit: _toDouble(json['deposit']),
      withdraw: _toDouble(json['withdraw']),
      experience: _toDouble(json['experience']),
      net: _toDouble(json['net']),
      byDate: ((json['by_date'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => FundDayStat.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// 单日资金聚合（`by_date` 列表项）：三类金额均为当日合计。
class FundDayStat {
  const FundDayStat({
    required this.date,
    required this.deposit,
    required this.withdraw,
    required this.experience,
  });

  final String date;
  final double deposit;
  final double withdraw;
  final double experience;

  /// 当日净额，与四卡「净投入」同口径。
  double get net => deposit - withdraw + experience;

  /// 是否没有任何金额（全 0 的日期不画柱）。
  bool get isEmpty => deposit == 0 && withdraw == 0 && experience == 0;

  factory FundDayStat.fromJson(Map<String, dynamic> json) {
    return FundDayStat(
      date: json['date'] as String? ?? '',
      deposit: _toDouble(json['deposit']),
      withdraw: _toDouble(json['withdraw']),
      experience: _toDouble(json['experience']),
    );
  }
}

/// 单笔外汇交易（`GET /investment/forex` 列表项）。
class ForexTrade {
  const ForexTrade({
    required this.id,
    required this.tradeDate,
    required this.symbol,
    required this.orderType,
    required this.openPrice,
    required this.lotSize,
    required this.commission,
    this.closePrice,
    this.pnl,
    required this.overnightFee,
    this.openTime,
    this.closeTime,
    this.holding,
    required this.status,
    this.note,
  });

  final int id;
  final String tradeDate;
  final String symbol;
  final String orderType;
  final double openPrice;
  final double lotSize;
  final double commission;
  final double? closePrice;
  final double? pnl;
  final double overnightFee;
  final String? openTime;
  final String? closeTime;
  final int? holding;
  final String status;
  final String? note;

  /// 是否持仓中（未平仓）。
  bool get isOpen => status == 'open';

  /// 方向文案：buy 做多 / sell 做空。
  String get orderTypeLabel => orderType == 'sell' ? '做空' : '做多';

  /// 净盈亏 = 盈亏 + 手续费 + 隔夜费（带符号），与后端汇总口径一致。
  double get netPnl => (pnl ?? 0) + commission + overnightFee;

  /// 列表时间：优先平仓时间，其次开仓时间，最后退回交易日。
  String get timeText {
    final String? iso = closeTime ?? openTime;
    if (iso == null || iso.isEmpty) {
      return tradeDate;
    }
    final DateTime? parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }
    final bool hasTime = iso.contains('T');
    return hasTime
        ? '${_two(parsed.month)}-${_two(parsed.day)} '
            '${_two(parsed.hour)}:${_two(parsed.minute)}'
        : tradeDate;
  }

  factory ForexTrade.fromJson(Map<String, dynamic> json) {
    return ForexTrade(
      id: _toInt(json['id']),
      tradeDate: json['trade_date'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      orderType: json['order_type'] as String? ?? 'buy',
      openPrice: _toDouble(json['open_price']),
      lotSize: _toDouble(json['lot_size']),
      commission: _toDouble(json['commission']),
      closePrice:
          json['close_price'] == null ? null : _toDouble(json['close_price']),
      pnl: json['pnl'] == null ? null : _toDouble(json['pnl']),
      overnightFee: _toDouble(json['overnight_fee']),
      openTime: json['open_time'] as String?,
      closeTime: json['close_time'] as String?,
      holding: json['holding'] == null ? null : _toInt(json['holding']),
      status: json['status'] as String? ?? 'closed',
      note: json['note'] as String?,
    );
  }
}

/// 资金记录类型选项：与网页端 `fundTypes` 一致，供 [AppSelectField] 使用。
const List<({String value, String label})> kFundTypes =
    <({String value, String label})>[
      (value: 'deposit', label: '入金'),
      (value: 'withdraw', label: '出金'),
      (value: 'experience', label: '体验金'),
    ];

/// 外汇统计汇总（`GET /investment/forex/stats` → `summary`）。
class ForexSummary {
  const ForexSummary({
    required this.accountValue,
    required this.netProfit,
    required this.grossPnl,
    required this.totalCommission,
    required this.totalOvernight,
    required this.tradeCount,
    required this.openCount,
    required this.winRate,
    required this.profitLossRatio,
    required this.profitFactor,
    required this.totalDeposit,
    required this.totalWithdraw,
    required this.totalExperience,
    required this.symbolCount,
  });

  final double accountValue;
  final double netProfit;
  final double grossPnl;
  final double totalCommission;
  final double totalOvernight;
  final int tradeCount;
  final int openCount;
  final double winRate;
  final double profitLossRatio;
  final double profitFactor;
  final double totalDeposit;
  final double totalWithdraw;
  final double totalExperience;
  final int symbolCount;

  factory ForexSummary.fromJson(Map<String, dynamic> json) {
    return ForexSummary(
      accountValue: _toDouble(json['account_value']),
      netProfit: _toDouble(json['net_profit']),
      grossPnl: _toDouble(json['gross_pnl']),
      totalCommission: _toDouble(json['total_commission']),
      totalOvernight: _toDouble(json['total_overnight']),
      tradeCount: _toInt(json['trade_count']),
      openCount: _toInt(json['open_count']),
      winRate: _toDouble(json['win_rate']),
      profitLossRatio: _toDouble(json['profit_loss_ratio']),
      profitFactor: _toDouble(json['profit_factor']),
      totalDeposit: _toDouble(json['total_deposit']),
      totalWithdraw: _toDouble(json['total_withdraw']),
      totalExperience: _toDouble(json['total_experience']),
      symbolCount: _toInt(json['symbol_count']),
    );
  }
}

/// 单品种盈亏（`by_symbol` 列表项）。
class ForexSymbolStat {
  const ForexSymbolStat({
    required this.symbol,
    required this.count,
    required this.winRate,
    required this.pnl,
  });

  final String symbol;
  final int count;
  final double winRate;
  final double pnl;

  factory ForexSymbolStat.fromJson(Map<String, dynamic> json) {
    return ForexSymbolStat(
      symbol: json['symbol'] as String? ?? '',
      count: _toInt(json['count']),
      winRate: _toDouble(json['win_rate']),
      pnl: _toDouble(json['pnl']),
    );
  }
}

/// 单时段交易笔数（`analysis.hour_dist` 列表项）。
class ForexHourStat {
  const ForexHourStat({required this.hour, required this.count});

  final int hour;
  final int count;

  /// 时段文案：`08:00`。
  String get label => '${_two(hour)}:00';

  factory ForexHourStat.fromJson(Map<String, dynamic> json) {
    return ForexHourStat(
      hour: _toInt(json['hour']),
      count: _toInt(json['count']),
    );
  }
}

/// 交易分析指标（`GET /investment/forex/stats` → `analysis`）。
class ForexAnalysis {
  const ForexAnalysis({
    required this.avgWin,
    required this.avgLoss,
    required this.maxSingleProfit,
    required this.maxSingleLoss,
    required this.maxDayProfit,
    required this.maxDayLoss,
    required this.maxDrawdown,
    required this.maxDrawdownPct,
    required this.profitFactor,
    required this.longestWinStreak,
    required this.longestLossStreak,
    required this.avgHoldingMinutes,
    required this.hourDist,
  });

  final double? avgWin;
  final double? avgLoss;
  final double? maxSingleProfit;
  final double? maxSingleLoss;
  final double? maxDayProfit;
  final double? maxDayLoss;
  final double maxDrawdown;

  /// 最大回撤率；累计净投入 ≤ 1 美元时后端返回 null（无有效基准）。
  final double? maxDrawdownPct;
  final double profitFactor;
  final int longestWinStreak;
  final int longestLossStreak;
  final int? avgHoldingMinutes;
  final List<ForexHourStat> hourDist;

  /// 平均持仓文案：`1 小时 25 分`；无平仓时间时显示「—」。
  String get avgHoldingText {
    final int? minutes = avgHoldingMinutes;
    if (minutes == null || minutes <= 0) {
      return '—';
    }
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
  }

  factory ForexAnalysis.fromJson(Map<String, dynamic> json) {
    double? optional(String key) =>
        json[key] == null ? null : _toDouble(json[key]);
    return ForexAnalysis(
      avgWin: optional('avg_win'),
      avgLoss: optional('avg_loss'),
      maxSingleProfit: optional('max_single_profit'),
      maxSingleLoss: optional('max_single_loss'),
      maxDayProfit: optional('max_day_profit'),
      maxDayLoss: optional('max_day_loss'),
      maxDrawdown: _toDouble(json['max_drawdown']),
      maxDrawdownPct: json['max_drawdown_pct'] == null
          ? null
          : _toDouble(json['max_drawdown_pct']),
      profitFactor: _toDouble(json['profit_factor']),
      longestWinStreak: _toInt(json['longest_win_streak']),
      longestLossStreak: _toInt(json['longest_loss_streak']),
      avgHoldingMinutes: json['avg_holding_minutes'] == null
          ? null
          : _toInt(json['avg_holding_minutes']),
      hourDist: ((json['hour_dist'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              ForexHourStat.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// 外汇统计聚合（`GET /investment/forex/stats?days=`）。
class ForexStats {
  const ForexStats({
    required this.summary,
    required this.bySymbol,
    required this.analysis,
  });

  final ForexSummary summary;
  final List<ForexSymbolStat> bySymbol;
  final ForexAnalysis analysis;

  factory ForexStats.fromJson(Map<String, dynamic> json) {
    return ForexStats(
      summary: ForexSummary.fromJson(
        (json['summary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      bySymbol: ((json['by_symbol'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              ForexSymbolStat.fromJson(item.cast<String, dynamic>()))
          .toList(),
      analysis: ForexAnalysis.fromJson(
        (json['analysis'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

/// 交易日历单日（`GET /investment/forex/calendar` → `days`）。
class ForexCalendarDay {
  const ForexCalendarDay({
    required this.day,
    required this.pnl,
    required this.count,
    required this.win,
    required this.loss,
    required this.position,
  });

  final int day;
  final double pnl;
  final int count;
  final int win;
  final int loss;
  final bool position;

  /// 是否有交易（无交易的日子不显示金额）。
  bool get active => count > 0;

  factory ForexCalendarDay.fromJson(Map<String, dynamic> json) {
    return ForexCalendarDay(
      day: _toInt(json['day']),
      pnl: _toDouble(json['pnl']),
      count: _toInt(json['count']),
      win: _toInt(json['win']),
      loss: _toInt(json['loss']),
      position: json['position'] as bool? ?? false,
    );
  }
}

/// 交易日历月汇总（`summary`）。
class ForexCalendarSummary {
  const ForexCalendarSummary({
    required this.monthPnl,
    required this.tradingDays,
    required this.winDays,
    required this.lossDays,
    required this.returnRate,
  });

  final double monthPnl;
  final int tradingDays;
  final int winDays;
  final int lossDays;
  final double returnRate;

  factory ForexCalendarSummary.fromJson(Map<String, dynamic> json) {
    return ForexCalendarSummary(
      monthPnl: _toDouble(json['month_pnl']),
      tradingDays: _toInt(json['trading_days']),
      winDays: _toInt(json['win_days']),
      lossDays: _toInt(json['loss_days']),
      returnRate: _toDouble(json['return_rate']),
    );
  }
}

/// 交易日历（`GET /investment/forex/calendar?month=YYYY-MM`）。
class ForexCalendar {
  const ForexCalendar({
    required this.year,
    required this.month,
    required this.days,
    required this.summary,
  });

  final int year;
  final int month;
  final List<ForexCalendarDay> days;
  final ForexCalendarSummary summary;

  /// `2026-09`：切换月份时的请求参数。
  String get monthKey =>
      '$year-${month < 10 ? '0$month' : '$month'}';

  factory ForexCalendar.fromJson(Map<String, dynamic> json) {
    return ForexCalendar(
      year: _toInt(json['year']),
      month: _toInt(json['month']),
      days: ((json['days'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              ForexCalendarDay.fromJson(item.cast<String, dynamic>()))
          .toList(),
      summary: ForexCalendarSummary.fromJson(
        (json['summary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}
