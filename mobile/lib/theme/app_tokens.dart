import 'package:flutter/material.dart';

/// LifeOS 2.0 · Apple 设计令牌。
///
/// 与旧版 `AppColors` / `AppTypography` 并存：2.0 新页面统一从这里取色与字号，
/// 旧页面继续使用原有令牌，避免一次性改色造成大面积回归。
/// 深浅色跟随 `Theme.of(context).brightness`，不做额外主题扩展。
@immutable
class AppTokens {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.green,
    required this.red,
    required this.orange,
    required this.fill,
    required this.fill2,
  });

  /// 浅色：iOS 分组列表底色 + 白色卡片。
  static const AppTokens light = AppTokens(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA),
    line: Color(0x4A3C3C43),
    text: Color(0xFF000000),
    text2: Color(0x993C3C43),
    text3: Color(0x4D3C3C43),
    accent: Color(0xFF007AFF),
    green: Color(0xFF34C759),
    red: Color(0xFFFF3B30),
    orange: Color(0xFFFF9500),
    fill: Color(0x29787880),
    fill2: Color(0x1A787880),
  );

  /// 深色：纯黑底 + #1C1C1E 卡片，强调色提亮为 iOS 深色变体。
  static const AppTokens dark = AppTokens(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    line: Color(0xA6545458),
    text: Color(0xFFFFFFFF),
    text2: Color(0x99EBEBF5),
    text3: Color(0x4DEBEBF5),
    accent: Color(0xFF0A84FF),
    green: Color(0xFF30D158),
    red: Color(0xFFFF453A),
    orange: Color(0xFFFF9F0A),
    fill: Color(0x52787880),
    fill2: Color(0x33787880),
  );

  /// 页面底色（分组背景）。
  final Color background;

  /// 卡片 / 快捷面板底色。
  final Color surface;

  /// 次级块（分段控件、次级容器）。
  final Color surface2;

  /// 发丝线 / 分隔线。
  final Color line;

  /// 主文字。
  final Color text;

  /// 次要文字。
  final Color text2;

  /// 辅助 / 占位文字。
  final Color text3;

  /// System Blue：全局唯一强调色。
  final Color accent;

  /// 上涨 / 收入 / 正常。
  final Color green;

  /// 下跌 / 支出 / 危险。
  final Color red;

  /// 临期 / 待处理。
  final Color orange;

  /// 圆形图标按钮、分段控件的填充色。
  final Color fill;

  /// 更浅的填充色（徽标、次级标签）。
  final Color fill2;

  /// 页面左右边距。
  static const double pagePadding = 20;

  /// 分组卡片圆角。
  static const double cardRadius = 14;

  /// 控件圆角（输入框 / 按钮 / 分段）。
  static const double controlRadius = 10;

  /// 发丝线宽度。
  static const double hairline = 0.5;

  /// 按当前主题亮度取令牌。
  static AppTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

/// 2.0 字阶：直接对应效果稿里的 SF Pro 层级。
///
/// 只定义字号 / 行高 / 字重，不写颜色；颜色由调用方从 [AppTokens] 取，
/// 这样同一字阶可以在不同底色上复用。
abstract final class AppType {
  static const TextStyle date = TextStyle(fontSize: 13, height: 1.3);

  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  static const TextStyle hero = TextStyle(
    fontSize: 48,
    height: 1.06,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.4,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle heroUnit = TextStyle(
    fontSize: 20,
    height: 1.1,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle heroSub = TextStyle(fontSize: 14, height: 1.4);

  static const TextStyle segment = TextStyle(fontSize: 14, height: 1);

  static const TextStyle rowTitle = TextStyle(fontSize: 16, height: 1.3);

  static const TextStyle rowMeta = TextStyle(fontSize: 13, height: 1.35);

  static const TextStyle rowValue = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle section = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle statLabel = TextStyle(fontSize: 12, height: 1.3);

  static const TextStyle statValue = TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle statUnit = TextStyle(fontSize: 11, height: 1.2);

  static const TextStyle badge = TextStyle(
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle action = TextStyle(fontSize: 15, height: 1.2);
}
