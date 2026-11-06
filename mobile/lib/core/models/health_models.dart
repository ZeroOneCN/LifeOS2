/// 健康域业务模型：步数统计、用药跟踪、睡眠体征、健身运动与体检指标。
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

/// 可空整数解析：接口未采集时保持 null，不能兜底成 0。
int? _toIntOrNull(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// 可空小数解析：接口未采集时保持 null。
double? _toDoubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

/// 可空小数取整（用于均值展示）：null 保持 null。
int? _toRoundedIntOrNull(Object? value) {
  final double? parsed = _toDoubleOrNull(value);
  return parsed?.round();
}

/// `23:10:00` → `23:10`；空值返回 null。
String? _shortTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value.length >= 5 ? value.substring(0, 5) : value;
}

/// 单日睡眠体征记录（`GET /health/vitals-sleep` 列表项）。
///
/// 深睡/浅睡/醒来次数等字段可能为 null（设备未采集），展示时须显示「—」。
class SleepRecord {
  const SleepRecord({
    required this.id,
    required this.recordDate,
    this.bedtime,
    this.wakeTime,
    this.durationMin,
    this.deepSleepMin,
    this.lightSleepMin,
    this.wakeCount,
    this.sleepQuality,
    this.note,
  });

  final int id;
  final String recordDate;
  final String? bedtime;
  final String? wakeTime;
  final int? durationMin;
  final int? deepSleepMin;
  final int? lightSleepMin;
  final int? wakeCount;
  final int? sleepQuality;
  final String? note;

  factory SleepRecord.fromJson(Map<String, dynamic> json) {
    return SleepRecord(
      id: _toInt(json['id']),
      recordDate: json['record_date'] as String? ?? '',
      bedtime: _shortTime(json['bedtime']),
      wakeTime: _shortTime(json['wake_time']),
      durationMin: _toIntOrNull(json['sleep_duration_min']),
      deepSleepMin: _toIntOrNull(json['deep_sleep_min']),
      lightSleepMin: _toIntOrNull(json['light_sleep_min']),
      wakeCount: _toIntOrNull(json['wake_count']),
      sleepQuality: _toIntOrNull(json['sleep_quality']),
      note: json['note'] as String?,
    );
  }
}

/// 睡眠趋势点（统计接口 `trend`，仅取本页需要的字段）。
class SleepTrendPoint {
  const SleepTrendPoint({
    required this.date,
    this.durationMin,
    this.deepSleepMin,
    this.lightSleepMin,
    this.wakeCount,
    this.sleepQuality,
  });

  final String date;
  final int? durationMin;
  final int? deepSleepMin;
  final int? lightSleepMin;
  final int? wakeCount;
  final int? sleepQuality;

  factory SleepTrendPoint.fromJson(Map<String, dynamic> json) {
    return SleepTrendPoint(
      date: json['record_date'] as String? ?? '',
      durationMin: _toIntOrNull(json['sleep_duration_min']),
      deepSleepMin: _toIntOrNull(json['deep_sleep_min']),
      lightSleepMin: _toIntOrNull(json['light_sleep_min']),
      wakeCount: _toIntOrNull(json['wake_count']),
      sleepQuality: _toIntOrNull(json['sleep_quality']),
    );
  }
}

/// 睡眠统计（`GET /health/vitals-sleep/stats?days=0`）。
class SleepStats {
  const SleepStats({
    required this.trend,
    required this.avgDurationMin,
    required this.avgDeepMin,
    required this.avgQuality,
    required this.recordCount,
  });

  final List<SleepTrendPoint> trend;
  final int? avgDurationMin;
  final double? avgDeepMin;
  final double? avgQuality;
  final int recordCount;

  /// 浅睡均值接口未直接返回，按趋势里的非空值求平均；全为空则 null。
  double? get avgLightMin {
    final List<int> values = trend
        .where((SleepTrendPoint point) => point.lightSleepMin != null)
        .map((SleepTrendPoint point) => point.lightSleepMin!)
        .toList(growable: false);
    if (values.isEmpty) {
      return null;
    }
    final int total = values.reduce((int a, int b) => a + b);
    return total / values.length;
  }

  /// 是否存在任何分阶段数据；false 时页面明确说明未采集。
  bool get hasStageData =>
      avgDeepMin != null ||
      avgLightMin != null ||
      trend.any((SleepTrendPoint point) =>
          point.deepSleepMin != null || point.lightSleepMin != null);

  factory SleepStats.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> avg =
        (json['avg'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    return SleepStats(
      trend: ((json['trend'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              SleepTrendPoint.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      avgDurationMin: _toRoundedIntOrNull(avg['sleep_duration_min']),
      avgDeepMin: _toDoubleOrNull(avg['deep_sleep_min']),
      avgQuality: _toDoubleOrNull(avg['sleep_quality']),
      recordCount: _toInt(json['record_count']),
    );
  }
}

/// 单条运动记录（`GET /health/fitness` 列表项）。
///
/// 消耗热量与距离可能为 null（无法按 MET 推算时），展示时须显示「—」。
class FitnessRecord {
  const FitnessRecord({
    required this.id,
    required this.recordDate,
    required this.exerciseType,
    required this.durationMin,
    this.calories,
    this.distanceKm,
    this.note,
  });

  final int id;
  final String recordDate;
  final String exerciseType;
  final int durationMin;
  final double? calories;
  final double? distanceKm;
  final String? note;

  factory FitnessRecord.fromJson(Map<String, dynamic> json) {
    return FitnessRecord(
      id: _toInt(json['id']),
      recordDate: json['record_date'] as String? ?? '',
      exerciseType: json['exercise_type'] as String? ?? '',
      durationMin: _toInt(json['duration_min']),
      calories: _toDoubleOrNull(json['calories']),
      distanceKm: _toDoubleOrNull(json['distance_km']),
      note: json['note'] as String?,
    );
  }
}

/// 按运动类型汇总（统计接口 `by_type`）。
class FitnessTypeSummary {
  const FitnessTypeSummary({
    required this.exerciseType,
    required this.count,
    required this.minutes,
    required this.calories,
  });

  final String exerciseType;
  final int count;
  final int minutes;
  final double calories;

  factory FitnessTypeSummary.fromJson(Map<String, dynamic> json) {
    return FitnessTypeSummary(
      exerciseType: json['exercise_type'] as String? ?? '',
      count: _toInt(json['count']),
      minutes: _toInt(json['minutes']),
      calories: _toDouble(json['calories']),
    );
  }
}

/// 运动统计（`GET /health/fitness/stats?days=`，days=0 表示全部）。
class FitnessStats {
  const FitnessStats({
    required this.totalCount,
    required this.totalMinutes,
    required this.totalCalories,
    required this.byType,
  });

  final int totalCount;
  final int totalMinutes;
  final double totalCalories;
  final List<FitnessTypeSummary> byType;

  factory FitnessStats.fromJson(Map<String, dynamic> json) {
    return FitnessStats(
      totalCount: _toInt(json['total_count']),
      totalMinutes: _toInt(json['total_minutes']),
      totalCalories: _toDouble(json['total_calories']),
      byType: ((json['by_type'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              FitnessTypeSummary.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// 单个体检指标的趋势点（统计接口 `items[].trend`）。
class CheckupTrendPoint {
  const CheckupTrendPoint({required this.date, this.value, this.result});

  final String date;
  final double? value;
  final String? result;

  factory CheckupTrendPoint.fromJson(Map<String, dynamic> json) {
    return CheckupTrendPoint(
      date: json['check_date'] as String? ?? '',
      value: _toDoubleOrNull(json['value']),
      result: json['result'] as String?,
    );
  }
}

/// 体检指标聚合（`GET /health/checkup/stats` 的 `items[]`）。
///
/// `latestValue` / `latestResult` 可能为 null（未采集或未判定），展示时用「—」。
class CheckupItem {
  const CheckupItem({
    required this.itemName,
    this.unit,
    this.referenceRange,
    this.refLow,
    this.refHigh,
    this.latestValue,
    this.latestDate,
    this.latestResult,
    required this.count,
    required this.trend,
  });

  final String itemName;
  final String? unit;
  final String? referenceRange;
  final double? refLow;
  final double? refHigh;
  final double? latestValue;
  final String? latestDate;
  final String? latestResult;
  final int count;
  final List<CheckupTrendPoint> trend;

  /// 是否超出参考范围（偏高/偏低）。
  bool get abnormal => latestResult == 'high' || latestResult == 'low';

  factory CheckupItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> latest =
        (json['latest'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    return CheckupItem(
      itemName: json['item_name'] as String? ?? '',
      unit: json['unit'] as String?,
      referenceRange: json['reference_range'] as String?,
      refLow: _toDoubleOrNull(json['ref_low']),
      refHigh: _toDoubleOrNull(json['ref_high']),
      latestValue: _toDoubleOrNull(latest['value']),
      latestDate: latest['check_date'] as String?,
      latestResult: latest['result'] as String?,
      count: _toInt(json['count']),
      trend: ((json['trend'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              CheckupTrendPoint.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// 体检统计（`GET /health/checkup/stats?days=0`）。
class CheckupStats {
  const CheckupStats({
    required this.items,
    required this.totalCount,
    required this.abnormalCount,
    required this.normalCount,
    required this.highCount,
    required this.lowCount,
    required this.statusLabel,
  });

  final List<CheckupItem> items;
  final int totalCount;
  final int abnormalCount;
  final int normalCount;
  final int highCount;
  final int lowCount;

  /// 后端给出的中文状态文案（normal/high/low → 正常/偏高/偏低）。
  final Map<String, String> statusLabel;

  factory CheckupStats.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> counts =
        (json['status_counts'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final Map<String, dynamic> labels =
        (json['status_label'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    return CheckupStats(
      items: ((json['items'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) => CheckupItem.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      totalCount: _toInt(json['total_count']),
      abnormalCount: _toInt(json['abnormal_count']),
      normalCount: _toInt(counts['normal']),
      highCount: _toInt(counts['high']),
      lowCount: _toInt(counts['low']),
      statusLabel: <String, String>{
        for (final MapEntry<String, dynamic> entry in labels.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
    );
  }
}
