import 'package:flutter/material.dart';

/// 设计色板：与 Web 端 `frontend/src/index.css` 的 OKLCH 令牌一一对应，
/// 这里固化的是换算后的 sRGB 十六进制值，页面中禁止再散写 hex。
///
/// 命名约定：
/// - `xxxLight` / `xxxDark` 分别对应 Web 端 `:root` 与 `.dark`；
/// - 语义色（success / warning / danger / info）同时提供 solid、容器（muted）两层，
///   与 Web 的 `--success` / `--success-muted` / `--success-muted-foreground` 对齐。
abstract final class AppColors {
  // 中性 · 浅色（Web: oklch(1/0.145/0.205/0.97/0.922 ...)）
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color foregroundLight = Color(0xFF0A0A0A);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color mutedLight = Color(0xFFF5F5F5);
  static const Color mutedForegroundLight = Color(0xFF737373);
  static const Color borderLight = Color(0xFFE5E5E5);
  static const Color primaryLight = Color(0xFF171717);
  static const Color onPrimaryLight = Color(0xFFFAFAFA);

  // 中性 · 深色
  static const Color backgroundDark = Color(0xFF0A0A0A);
  static const Color foregroundDark = Color(0xFFFAFAFA);
  static const Color cardDark = Color(0xFF171717);
  static const Color mutedDark = Color(0xFF262626);
  static const Color mutedForegroundDark = Color(0xFFA1A1A1);
  static const Color borderDark = Color(0x1AFFFFFF); // oklch(1 0 0 / 10%)
  static const Color primaryDark = Color(0xFFE5E5E5);
  static const Color onPrimaryDark = Color(0xFF171717);

  // 语义 · 浅色
  static const Color successLight = Color(0xFF00A63E);
  static const Color successContainerLight = Color(0xFFDCFCE7);
  static const Color onSuccessContainerLight = Color(0xFF016630);
  static const Color warningLight = Color(0xFFE17100);
  static const Color warningContainerLight = Color(0xFFFEF3C6);
  static const Color onWarningContainerLight = Color(0xFF973C00);
  static const Color dangerLight = Color(0xFFE7000B);
  static const Color dangerContainerLight = Color(0xFFFFE2E2);
  static const Color onDangerContainerLight = Color(0xFF9F0712);
  static const Color infoLight = Color(0xFF0084D1);
  static const Color infoContainerLight = Color(0xFFDBEAFE);
  static const Color onInfoContainerLight = Color(0xFF193CB8);

  // 语义 · 深色
  static const Color successDark = Color(0xFF05DF72);
  static const Color successContainerDark = Color(0xFF032E15);
  static const Color onSuccessContainerDark = Color(0xFF7BF1A8);
  static const Color warningDark = Color(0xFFFFB900);
  static const Color warningContainerDark = Color(0xFF461901);
  static const Color onWarningContainerDark = Color(0xFFFEE685);
  static const Color dangerDark = Color(0xFFFF6467);
  static const Color dangerContainerDark = Color(0xFF460809);
  static const Color onDangerContainerDark = Color(0xFFFFC9C9);
  static const Color infoDark = Color(0xFF00BCFF);
  static const Color infoContainerDark = Color(0xFF162456);
  static const Color onInfoContainerDark = Color(0xFFBEDBFF);

  // 纯白 / 深色文字：语义 solid 色块上的前景
  static const Color onSemanticLight = Color(0xFFFAFAFA);
  static const Color onSemanticDark = Color(0xFF171717);
}
