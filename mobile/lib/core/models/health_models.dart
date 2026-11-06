/// 健康域业务模型：步数统计与用药跟踪。
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

/// 每日步数趋势点（统计接口 `trend`）。
class StepTrendPoint {
  const StepTrendPoint({
    required this.date,
    required this.steps,
    required this.distanceKm,
    required this.calories,
  });

  final String date;
  final int steps;
  final double distanceKm;
  final double calories;

  factory StepTrendPoint.fromJson(Map<String, dynamic> json) {
    return StepTrendPoint(
      date: json['record_date'] as String? ?? '',
      steps: _toInt(json['steps']),
      distanceKm: _toDouble(json['distance_km']),
      calories: _toDouble(json['calories']),
    );
  }
}

/// 分时段累计（统计接口 `by_period`）。
class StepPeriod {
  const StepPeriod({required this.period, required this.steps});

  final String period;
  final int steps;

  /// `full` 是整日汇总行，与分时段相加会重复，展示时单独说明。
  bool get isFull => period == 'full';

  factory StepPeriod.fromJson(Map<String, dynamic> json) {
    return StepPeriod(
      period: json['period'] as String? ?? '',
      steps: _toInt(json['steps']),
    );
  }
}

/// 步数统计（`GET /health/steps/stats?days=`）。
class StepStats {
  const StepStats({
    required this.trend,
    required this.byPeriod,
    required this.avgSteps,
    required this.maxSteps,
    required this.totalSteps,
    required this.recordCount,
  });

  final List<StepTrendPoint> trend;
  final List<StepPeriod> byPeriod;
  final int? avgSteps;
  final int? maxSteps;
  final int totalSteps;
  final int recordCount;

  factory StepStats.fromJson(Map<String, dynamic> json) {
    return StepStats(
      trend: ((json['trend'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              StepTrendPoint.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      byPeriod: ((json['by_period'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => StepPeriod.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      avgSteps: json['avg_steps'] == null ? null : _toInt(json['avg_steps']),
      maxSteps: json['max_steps'] == null ? null : _toInt(json['max_steps']),
      totalSteps: _toInt(json['total_steps']),
      recordCount: _toInt(json['record_count']),
    );
  }
}

/// 单日用药记录（`GET /health/medication` 列表项）。
///
/// 每天一条记录，早/午/晚分别有粒数与是否已服。
class MedicationRecord {
  const MedicationRecord({
    required this.id,
    required this.recordDate,
    required this.medicineName,
    required this.doseBreakfast,
    required this.doseLunch,
    required this.doseDinner,
    required this.takenBreakfast,
    required this.takenLunch,
    required this.takenDinner,
    this.frequency,
    this.note,
  });

  final int id;
  final String recordDate;
  final String medicineName;
  final int doseBreakfast;
  final int doseLunch;
  final int doseDinner;
  final bool takenBreakfast;
  final bool takenLunch;
  final bool takenDinner;
  final String? frequency;
  final String? note;

  /// 当天应服总粒数。
  int get totalDoses => doseBreakfast + doseLunch + doseDinner;

  /// 当天已服总粒数。
  int get takenDoses =>
      (takenBreakfast ? doseBreakfast : 0) +
      (takenLunch ? doseLunch : 0) +
      (takenDinner ? doseDinner : 0);

  bool get isComplete => totalDoses > 0 && takenDoses >= totalDoses;

  /// 仅用于离线打卡的本地乐观更新：改写某餐次的已服状态。
  MedicationRecord copyWith({
    bool? takenBreakfast,
    bool? takenLunch,
    bool? takenDinner,
  }) {
    return MedicationRecord(
      id: id,
      recordDate: recordDate,
      medicineName: medicineName,
      doseBreakfast: doseBreakfast,
      doseLunch: doseLunch,
      doseDinner: doseDinner,
      takenBreakfast: takenBreakfast ?? this.takenBreakfast,
      takenLunch: takenLunch ?? this.takenLunch,
      takenDinner: takenDinner ?? this.takenDinner,
      frequency: frequency,
      note: note,
    );
  }

  factory MedicationRecord.fromJson(Map<String, dynamic> json) {
    return MedicationRecord(
      id: _toInt(json['id']),
      recordDate: json['record_date'] as String? ?? '',
      medicineName: json['medicine_name'] as String? ?? '',
      doseBreakfast: _toInt(json['dose_breakfast']),
      doseLunch: _toInt(json['dose_lunch']),
      doseDinner: _toInt(json['dose_dinner']),
      takenBreakfast: json['taken_breakfast'] as bool? ?? false,
      takenLunch: json['taken_lunch'] as bool? ?? false,
      takenDinner: json['taken_dinner'] as bool? ?? false,
      frequency: json['frequency'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// 分餐次统计（统计接口 `by_slot`）。
class MedSlot {
  const MedSlot({
    required this.slot,
    required this.label,
    required this.total,
    required this.taken,
  });

  final String slot;
  final String label;
  final int total;
  final int taken;

  factory MedSlot.fromJson(Map<String, dynamic> json) {
    return MedSlot(
      slot: json['meal_slot'] as String? ?? '',
      label: json['meal_label'] as String? ?? '',
      total: _toInt(json['total']),
      taken: _toInt(json['taken']),
    );
  }
}

/// 每日服药趋势（统计接口 `trend`）。
class MedDayTrend {
  const MedDayTrend({
    required this.date,
    required this.total,
    required this.taken,
  });

  final String date;
  final int total;
  final int taken;

  factory MedDayTrend.fromJson(Map<String, dynamic> json) {
    return MedDayTrend(
      date: json['record_date'] as String? ?? '',
      total: _toInt(json['total']),
      taken: _toInt(json['taken']),
    );
  }
}

/// 用药统计（`GET /health/medication/stats?days=`）。
class MedicationStats {
  const MedicationStats({
    required this.todayTaken,
    required this.todayPending,
    required this.adherenceRate,
    required this.bySlot,
    required this.trend,
    required this.totalCount,
    required this.totalPills,
  });

  final int todayTaken;
  final int todayPending;
  final double adherenceRate;
  final List<MedSlot> bySlot;
  final List<MedDayTrend> trend;
  final int totalCount;
  final int totalPills;

  factory MedicationStats.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> today =
        (json['today'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    return MedicationStats(
      todayTaken: _toInt(today['taken_count']),
      todayPending: _toInt(today['pending_count']),
      adherenceRate: _toDouble(json['adherence_rate']),
      bySlot: ((json['by_slot'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => MedSlot.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      trend: ((json['trend'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              MedDayTrend.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      totalCount: _toInt(json['total_count']),
      totalPills: _toInt(json['total_pills']),
    );
  }
}

/// 药品库存（`GET /health/medication/stocks` 列表项）。
class MedStock {
  const MedStock({
    required this.id,
    required this.name,
    required this.quantity,
    required this.threshold,
    required this.unit,
    required this.isLow,
    required this.purchased,
    required this.consumed,
    this.avgDaily,
    this.daysLeft,
    this.predictedDate,
  });

  final int id;
  final String name;
  final double quantity;
  final double threshold;
  final String unit;
  final bool isLow;
  final double purchased;
  final int consumed;
  final double? avgDaily;
  final int? daysLeft;
  final String? predictedDate;

  factory MedStock.fromJson(Map<String, dynamic> json) {
    return MedStock(
      id: _toInt(json['id']),
      name: json['medicine_name'] as String? ?? '',
      quantity: _toDouble(json['stock_qty']),
      threshold: _toDouble(json['threshold']),
      unit: json['unit'] as String? ?? '粒',
      isLow: json['is_low'] as bool? ?? false,
      purchased: _toDouble(json['purchased']),
      consumed: _toInt(json['consumed']),
      avgDaily:
          json['avg_daily'] == null ? null : _toDouble(json['avg_daily']),
      daysLeft: json['days_left'] == null ? null : _toInt(json['days_left']),
      predictedDate: json['predicted_date'] as String?,
    );
  }
}
