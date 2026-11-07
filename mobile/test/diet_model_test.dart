import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/core/models/health_models.dart';
import 'package:lifeos_mobile/core/utils/formatters.dart';

/// 饮食记录模型：餐次口径、空值解析、每日小计与今日汇总同源。
void main() {
  test('餐次展示名与排序权重符合后端枚举与网页端口径', () {
    expect(mealTypeLabel('breakfast'), '早餐');
    expect(mealTypeLabel('lunch'), '午餐');
    expect(mealTypeLabel('dinner'), '晚餐');
    expect(mealTypeLabel('snack'), '加餐');
    // 历史未知值原样返回，排序排在已知餐次之后。
    expect(mealTypeLabel('midnight'), 'midnight');
    expect(mealTypeOrder('breakfast'), 0);
    expect(mealTypeOrder('lunch'), 1);
    expect(mealTypeOrder('dinner'), 2);
    expect(mealTypeOrder('snack'), 3);
    expect(mealTypeOrder('midnight'), kMealTypes.length);
  });

  test('记录解析：营养素缺失保持 null，不兜底成 0', () {
    final DietRecord record = DietRecord.fromJson(<String, dynamic>{
      'id': 7,
      'record_date': '2026-11-07',
      'meal_type': 'breakfast',
      'food_name': '黑咖啡',
      'weight_g': 2,
      'calories': 0,
      'protein': null,
      'carbs': 0,
      'note': null,
    });
    expect(record.recordDate, '2026-11-07');
    expect(record.calories, 0);
    expect(record.protein, isNull);
    expect(record.carbs, 0);
    expect(record.fat, isNull);
  });

  test('今日汇总与列表每日小计取自同一条 trend，缺失日期返回 null', () {
    final DietStats stats = DietStats.fromJson(<String, dynamic>{
      'trend': <Map<String, dynamic>>[
        <String, dynamic>{
          'record_date': '2026-11-06',
          'calories': 1200.5,
          'protein': 60.0,
          'carbs': 140.0,
          'fat': 30.0,
          'count': 3,
        },
        <String, dynamic>{
          'record_date': '2026-11-07',
          'calories': 480.0,
          'protein': 32.5,
          'carbs': 55.0,
          'fat': 12.0,
          'count': 2,
        },
      ],
      'total_count': 5,
      'total_calories': 1680.5,
      'total_protein': 92.5,
      'avg_calories_per_day': 840.3,
    });

    final DietDayTotals today = stats.forDate('2026-11-07')!;
    expect(today.calories, 480.0);
    expect(today.protein, 32.5);
    expect(today.count, 2);
    expect(stats.forDate('2026-11-06')!.count, 3);
    expect(stats.forDate('2026-11-08'), isNull);
  });

  test('紧凑数值：去掉多余尾零，留空显示「—」', () {
    expect(formatCompact(100.0), '100');
    expect(formatCompact(12.50), '12.5');
    expect(formatCompact(0), '0');
    expect(formatCompact(null), '—');
  });
}
