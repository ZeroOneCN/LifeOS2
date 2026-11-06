import 'package:flutter/material.dart';

/// 字阶与字体族。
///
/// 方案口径：标题 24 / 正文 16 / 辅助 12；数字统一等宽（tabular figures），
/// 避免金额、百分比在列表中跳动。
abstract final class AppTypography {
  /// 中文字体回退链：Android 自带 Noto Sans CJK，桌面端兜底雅黑。
  static const List<String> fontFallback = <String>[
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static const TextStyle titleLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle bodyLarge = TextStyle(fontSize: 16, height: 1.5);

  static const TextStyle bodyMedium = TextStyle(fontSize: 14, height: 1.5);

  static const TextStyle bodySmall = TextStyle(fontSize: 12, height: 1.4);

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// 金额 / 数字：等宽数字（tabular figures）
  static const TextStyle amountLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle amountMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextTheme textTheme = TextTheme(
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelMedium: labelMedium,
    labelSmall: bodySmall,
  );
}
