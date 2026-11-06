import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/theme/app_theme.dart';

void main() {
  test('浅色与深色主题可构建且语义色齐全', () {
    final ThemeData light = AppTheme.light();
    final ThemeData dark = AppTheme.dark();

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.extension<AppSemanticColors>(), isNotNull);
    expect(dark.extension<AppSemanticColors>(), isNotNull);
    expect(light.textTheme.titleLarge?.fontSize, 24);
    expect(dark.colorScheme.surface, const Color(0xFF0A0A0A));
  });
}
