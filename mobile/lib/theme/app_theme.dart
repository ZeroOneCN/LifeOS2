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
            borderRadius: BorderRadius.circular(12),
          ),
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
          borderRadius: BorderRadius.circular(28),
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

  /// 显式对齐 Web 色板：先 fromSeed 保证 M3 内部派生字段完整，再覆盖中性面与语义 error。
  static ColorScheme _colorScheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      brightness: brightness,
    );
    return base.copyWith(
      primary: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      onPrimary: isDark ? AppColors.onPrimaryDark : AppColors.onPrimaryLight,
      secondary: isDark ? AppColors.mutedDark : AppColors.mutedLight,
      onSecondary: isDark ? AppColors.foregroundDark : AppColors.foregroundLight,
      surface: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      onSurface: isDark ? AppColors.foregroundDark : AppColors.foregroundLight,
      onSurfaceVariant:
          isDark ? AppColors.mutedForegroundDark : AppColors.mutedForegroundLight,
      error: isDark ? AppColors.dangerDark : AppColors.dangerLight,
      onError:
          isDark ? AppColors.onSemanticDark : AppColors.onSemanticLight,
      outline: isDark ? AppColors.borderDark : AppColors.borderLight,
      outlineVariant: isDark ? AppColors.borderDark : AppColors.borderLight,
      surfaceContainerLowest:
          isDark ? AppColors.backgroundDark : AppColors.cardLight,
      surfaceContainerLow:
          isDark ? AppColors.cardDark : AppColors.backgroundLight,
      surfaceContainer: isDark ? AppColors.mutedDark : AppColors.mutedLight,
      surfaceContainerHigh: isDark ? AppColors.mutedDark : AppColors.mutedLight,
      surfaceContainerHighest:
          isDark ? AppColors.mutedDark : AppColors.mutedLight,
    );
  }
}
