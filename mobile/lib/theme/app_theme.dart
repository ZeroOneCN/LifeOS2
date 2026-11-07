import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// 语义色扩展（success / warning / danger / info）。
///
/// M3 的 ColorScheme 只有 error，没有 success/warning/info，
/// 统一通过 ThemeExtension 暴露，页面里用 `context.semanticColors` 取。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.successLight,
    onSuccess: AppColors.onSemanticLight,
    successContainer: AppColors.successContainerLight,
    onSuccessContainer: AppColors.onSuccessContainerLight,
    warning: AppColors.warningLight,
    onWarning: AppColors.onSemanticLight,
    warningContainer: AppColors.warningContainerLight,
    onWarningContainer: AppColors.onWarningContainerLight,
    danger: AppColors.dangerLight,
    onDanger: AppColors.onSemanticLight,
    dangerContainer: AppColors.dangerContainerLight,
    onDangerContainer: AppColors.onDangerContainerLight,
    info: AppColors.infoLight,
    onInfo: AppColors.onSemanticLight,
    infoContainer: AppColors.infoContainerLight,
    onInfoContainer: AppColors.onInfoContainerLight,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: AppColors.successDark,
    onSuccess: AppColors.onSemanticDark,
    successContainer: AppColors.successContainerDark,
    onSuccessContainer: AppColors.onSuccessContainerDark,
    warning: AppColors.warningDark,
    onWarning: AppColors.onSemanticDark,
    warningContainer: AppColors.warningContainerDark,
    onWarningContainer: AppColors.onWarningContainerDark,
    danger: AppColors.dangerDark,
    onDanger: AppColors.onSemanticDark,
    dangerContainer: AppColors.dangerContainerDark,
    onDangerContainer: AppColors.onDangerContainerDark,
    info: AppColors.infoDark,
    onInfo: AppColors.onSemanticDark,
    infoContainer: AppColors.infoContainerDark,
    onInfoContainer: AppColors.onInfoContainerDark,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer:
          Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  /// 语义色（success / warning / danger / info）
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}

/// 圆角令牌：全 App 的按钮、Tab 指示器等「控件类」统一 8dp。
///
/// 卡片、输入框属于「容器类」，各自保持原有 12dp，不与控件混用。
abstract final class AppRadii {
  /// 控件圆角（按钮 / Tab 指示器 / 分段选择器）。
  static const double control = 8;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = _colorScheme(brightness);
    final AppSemanticColors semantic =
        isDark ? AppSemanticColors.dark : AppSemanticColors.light;
    final Color cardColor = isDark ? AppColors.cardDark : AppColors.cardLight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamilyFallback: AppTypography.fontFallback,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      extensions: <ThemeExtension<dynamic>>[semantic],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            AppTypography.titleLarge.copyWith(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 深色模式下 primary 接近白色，靠颜色深浅区分选中太弱，
        // 因此叠加更明显的选中胶囊 + 图标放大 + 未选态降透明度。
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
        // 选中指示器只做小圆角，不用 Material 默认的大胶囊。
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return AppTypography.labelMedium.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: selected ? 28 : 24,
            color: selected
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: isDark ? 0.72 : 0.9),
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 注意：不能用 Size.fromHeight（minWidth=infinity），
          // 否则 FilledButton 放进 Row 时会强制无限宽度并触发布局断言。
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      // 次操作 / 危险操作都由 OutlinedButton 承担：统一 48 高、8 圆角，
      // 与主操作同尺寸，成对出现时不会一个长一个短。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      // 分段选择器（区间 / 类型切换）：8dp 小圆角 + 黑白灰选中态，不用大胶囊。
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHigh,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: scheme.outlineVariant),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.cardDark : AppColors.foregroundLight,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.foregroundDark : AppColors.onPrimaryLight,
        ),
      ),
    );
  }

  /// 显式覆盖所有会露出的 M3 色槽，避免 `fromSeed` 的蓝色中性色泄漏。
  ///
  /// `fromSeed(Color(0xFF171717))` 虽然种子近黑，但 M3 会用种子推导出一整套
  /// 带蓝色相的 tonal palette（`secondaryContainer` 就是浅蓝），一旦只覆盖
  /// primary / surface 等少数槽位，Tab 选中态就会露出默认蓝。因此这里把
  /// primary / secondary / tertiary / container / fixed / surfaceTint 全量
  /// 收敛到黑白灰体系；红色只保留在 error（危险语义）。
  static ColorScheme _colorScheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      brightness: brightness,
    );
    final Color primary = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final Color onPrimary =
        isDark ? AppColors.onPrimaryDark : AppColors.onPrimaryLight;
    final Color surface = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final Color onSurface =
        isDark ? AppColors.foregroundDark : AppColors.foregroundLight;
    final Color container = isDark ? AppColors.mutedDark : AppColors.mutedLight;
    final Color onContainer = onSurface;
    final Color neutral =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForegroundLight;
    return base.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
      secondary: neutral,
      onSecondary: isDark ? AppColors.foregroundDark : AppColors.backgroundLight,
      secondaryContainer: container,
      onSecondaryContainer: onContainer,
      tertiary: neutral,
      onTertiary: isDark ? AppColors.foregroundDark : AppColors.backgroundLight,
      tertiaryContainer: container,
      onTertiaryContainer: onContainer,
      // fixed / dim 系列同样来自种子色，一旦被新组件使用就会露出蓝色。
      primaryFixed: container,
      primaryFixedDim: container,
      onPrimaryFixed: onContainer,
      onPrimaryFixedVariant: neutral,
      secondaryFixed: container,
      secondaryFixedDim: container,
      onSecondaryFixed: onContainer,
      onSecondaryFixedVariant: neutral,
      tertiaryFixed: container,
      tertiaryFixedDim: container,
      onTertiaryFixed: onContainer,
      onTertiaryFixedVariant: neutral,
      inversePrimary: neutral,
      surfaceTint: Colors.transparent,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: neutral,
      surfaceBright: isDark ? AppColors.cardDark : AppColors.cardLight,
      surfaceDim: surface,
      error: isDark ? AppColors.dangerDark : AppColors.dangerLight,
      onError:
          isDark ? AppColors.onSemanticDark : AppColors.onSemanticLight,
      outline: isDark ? AppColors.borderDark : AppColors.borderLight,
      outlineVariant: isDark ? AppColors.borderDark : AppColors.borderLight,
      surfaceContainerLowest:
          isDark ? AppColors.backgroundDark : AppColors.cardLight,
      surfaceContainerLow:
          isDark ? AppColors.cardDark : AppColors.backgroundLight,
      surfaceContainer: container,
      surfaceContainerHigh: container,
      surfaceContainerHighest: container,
    );
  }
}
