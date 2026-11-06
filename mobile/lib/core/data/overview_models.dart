/// 五域「总览层」数据模型：只映射 Tab 根页摘要需要的字段。
///
/// 字段与后端总览接口一一对应：
/// - `backend/app/api/routes/health/overview.py`
/// - `backend/app/api/routes/finance/overview.py`
/// - `backend/app/api/routes/lifestyle/overview.py`
/// - `backend/app/api/routes/investment/overview.py`
///
/// 业务明细（账单、物品、交易等列表）不在总览层，留待后续批次。
library;

Map<String, dynamic>? _asMap(dynamic value) {
  return value is Map ? value.cast<String, dynamic>() : null;
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((Map item) => item.cast<String, dynamic>())
      .toList(growable: false);
}

num? _toNum(dynamic value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

int? _toInt(dynamic value) => _toNum(value)?.toInt();

double? _toDouble(dynamic value) => _toNum(value)?.toDouble();

/// 今日用药条目（总览层只给名称、剂量、是否已服）。
class MedicationItem {
  const MedicationItem({
    required this.name,
    this.dosage,
    required this.taken,
  });

  factory MedicationItem.fromJson(Map<String, dynamic> json) {
    return MedicationItem(
      name: json['medicine_name'] as String? ?? '',
      dosage: json['dosage'] as String?,
      taken: json['taken'] as bool? ?? false,
    );
  }

  final String name;
  final String? dosage;
  final bool taken;
}

/// 健康域总览（GET /health/overview）。
class HealthOverview {
  const HealthOverview({
    this.steps,
    this.stepsDate,
    this.distanceKm,
    this.calories,
    this.takenCount,
    this.pendingCount,
    this.medicationItems = const <MedicationItem>[],
    this.weekStepsAvg,
    this.weekSleepAvgMin,
    this.weekFitnessCount,
  });

  factory HealthOverview.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? steps = _asMap(json['latest_steps']);
    final Map<String, dynamic>? medication = _asMap(json['today_medication']);
    final Map<String, dynamic>? week = _asMap(json['week_summary']);
    return HealthOverview(
      steps: _toInt(steps?['steps']),
      stepsDate: steps?['record_date'] as String?,
      distanceKm: _toDouble(steps?['distance_km']),
      calories: _toInt(steps?['calories']),
      takenCount: _toInt(medication?['taken_count']),
      pendingCount: _toInt(medication?['pending_count']),
      medicationItems: _asMapList(medication?['items'])
          .map(MedicationItem.fromJson)
          .toList(growable: false),
      weekStepsAvg: _toInt(week?['steps_avg']),
      weekSleepAvgMin: _toInt(week?['sleep_avg_min']),
      weekFitnessCount: _toInt(week?['fitness_count']),
    );
  }

  /// 最新一条步数记录的步数（不是当日累计）。
  final int? steps;
  final String? stepsDate;
  final double? distanceKm;
  final int? calories;

  final int? takenCount;
  final int? pendingCount;
  final List<MedicationItem> medicationItems;

  final int? weekStepsAvg;
  final int? weekSleepAvgMin;
  final int? weekFitnessCount;
}

/// 待还账单/账单待办条目。
class PendingBill {
  const PendingBill({
    required this.title,
    this.remaining,
    this.dueDate,
  });

  factory PendingBill.fromJson(Map<String, dynamic> json) {
    return PendingBill(
      title: json['bill_type'] as String? ?? '账单',
      remaining: _toDouble(json['remaining'] ?? json['amount']),
      dueDate: json['due_date'] as String?,
    );
  }

  final String title;
  final double? remaining;
  final String? dueDate;
}

/// 财务域总览（GET /finance/overview）。
class FinanceOverview {
  const FinanceOverview({
    this.monthExpense,
    this.unpaidBills,
    this.outstandingDebt,
    this.outstandingLoans,
    this.investPnl,
    this.pendingBills = const <PendingBill>[],
  });

  factory FinanceOverview.fromJson(Map<String, dynamic> json) {
    return FinanceOverview(
      monthExpense: _toDouble(json['month_expense']),
      unpaidBills: _toDouble(json['unpaid_bills']),
      outstandingDebt: _toDouble(json['outstanding_debt']),
      outstandingLoans: _toDouble(json['outstanding_loans']),
      investPnl: _toDouble(json['invest_pnl']),
      pendingBills: _asMapList(json['pending_bills'])
          .map(PendingBill.fromJson)
          .toList(growable: false),
    );
  }

  /// 本月合计支出（购物 + 旅行 + 水电 + 订阅 + 房租 + 网贷已还）。
  final double? monthExpense;

  /// 本月网贷账单未还金额。
  final double? unpaidBills;

  /// 借还债务未结清余额。
  final double? outstandingDebt;

  /// 网贷全量未还余额。
  final double? outstandingLoans;

  final double? investPnl;
  final List<PendingBill> pendingBills;
}

/// 即将到期物品。
class ExpiringItem {
  const ExpiringItem({required this.name, this.daysLeft});

  factory ExpiringItem.fromJson(Map<String, dynamic> json) {
    return ExpiringItem(
      name: json['item_name'] as String? ?? '物品',
      daysLeft: _toInt(json['days_left']),
    );
  }

  final String name;
  final int? daysLeft;
}

/// 生活域总览（GET /lifestyle/overview）。
class LifestyleOverview {
  const LifestyleOverview({
    this.itemTotal,
    this.itemInUse,
    this.itemValue,
    this.itemExpiring,
    this.itemExpired,
    this.phoneTotal,
    this.phoneActive,
    this.bankTotal,
    this.bankActive,
    this.monthDeduct,
    this.expiringItems = const <ExpiringItem>[],
  });

  factory LifestyleOverview.fromJson(Map<String, dynamic> json) {
    return LifestyleOverview(
      itemTotal: _toInt(json['item_total']),
      itemInUse: _toInt(json['item_in_use']),
      itemValue: _toDouble(json['item_value']),
      itemExpiring: _toInt(json['item_expiring']),
      itemExpired: _toInt(json['item_expired']),
      phoneTotal: _toInt(json['phone_total']),
      phoneActive: _toInt(json['phone_active']),
      bankTotal: _toInt(json['bank_total']),
      bankActive: _toInt(json['bank_active']),
      monthDeduct: _toDouble(json['month_deduct']),
      expiringItems: _asMapList(json['expiring_items'])
          .map(ExpiringItem.fromJson)
          .toList(growable: false),
    );
  }

  final int? itemTotal;
  final int? itemInUse;
  final double? itemValue;
  final int? itemExpiring;
  final int? itemExpired;

  final int? phoneTotal;
  final int? phoneActive;
  final int? bankTotal;
  final int? bankActive;

  final double? monthDeduct;
  final List<ExpiringItem> expiringItems;

  /// 卡片在册总数（手机卡 + 银行卡）。
  int? get cardTotal {
    if (phoneTotal == null && bankTotal == null) {
      return null;
    }
    return (phoneTotal ?? 0) + (bankTotal ?? 0);
  }
}

/// 投资域总览（GET /investment/overview）。
class InvestmentOverview {
  const InvestmentOverview({
    this.accountValue,
    this.netProfit,
    this.tradeCount,
    this.openCount,
    this.winRate,
    this.symbolCount,
    this.reportCount,
  });

  factory InvestmentOverview.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? summary = _asMap(json['summary']);
    return InvestmentOverview(
      accountValue: _toDouble(summary?['account_value']),
      netProfit: _toDouble(summary?['net_profit']),
      tradeCount: _toInt(summary?['trade_count']),
      openCount: _toInt(summary?['open_count']),
      winRate: _toDouble(summary?['win_rate']),
      symbolCount: _toInt(summary?['symbol_count']),
      reportCount: _toInt(json['report_count']),
    );
  }

  final double? accountValue;
  final double? netProfit;
  final int? tradeCount;
  final int? openCount;
  final double? winRate;
  final int? symbolCount;
  final int? reportCount;
}

