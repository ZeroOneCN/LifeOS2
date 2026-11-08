import 'package:flutter/material.dart' show ThemeMode, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 普通偏好存储（非敏感）：服务器地址、主题、字体缩放。
/// 敏感令牌不落这里，见 `TokenStore`（flutter_secure_storage）。
class PreferencesService {
  PreferencesService._(this._prefs);

  final SharedPreferences _prefs;

  static const String _baseUrlKey = 'server.base_url';
  static const String _themeModeKey = 'ui.theme_mode';
  static const String _fontScaleKey = 'ui.font_scale_ratio';

  /// 全局主题模式：`MaterialApp` 监听它，设置页切换后立即生效并在冷启动恢复。
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  /// 全局字体缩放比例：`null` = 跟随系统；非空表示「相对系统缩放」的倍数。
  ///
  /// 取值在 [0.8, 1.5] 之内（脏数据一律回退跟随系统），
  /// `MaterialApp` 在首帧就读取它，冷启动不会先闪默认字号再跳变。
  final ValueNotifier<double?> fontScaleRatio = ValueNotifier<double?>(null);

  /// 创建实例；必须在 `runApp` 之前 await 完成。
  static Future<PreferencesService> create() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PreferencesService service = PreferencesService._(prefs);
    service.themeMode.value = _parseThemeMode(prefs.getString(_themeModeKey));
    service.fontScaleRatio.value =
        _parseFontScaleRatio(prefs.getString(_fontScaleKey));
    return service;
  }

  /// 持久化的主题值 → `ThemeMode`；未知值一律回退跟随系统。
  static ThemeMode _parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// 当前服务器地址（含 `/api/v1` 前缀），未设置时回退默认值。
  String get baseUrl => _prefs.getString(_baseUrlKey) ?? AppConfig.defaultBaseUrl;

  /// 持久化服务器地址（由设置页校验、规范化后调用）。
  Future<void> setBaseUrl(String value) async {
    await _prefs.setString(_baseUrlKey, value);
  }

  /// 切换深浅色：先更新内存（界面立刻生效），再落盘供下次冷启动读取。
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }

  /// 持久化的字体缩放值 → 倍数；`null` / 非法 / 越界一律回退「跟随系统」。
  static double? _parseFontScaleRatio(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final double? value = double.tryParse(raw);
    if (value == null || value < 0.8 || value > 1.5) {
      return null;
    }
    return value;
  }

  /// 设置字体缩放：`null` 表示跟随系统。
  ///
  /// 先更新内存让界面立刻重排，再落盘；写入失败不影响本次会话的显示。
  Future<void> setFontScaleRatio(double? ratio) async {
    final double? normalized = ratio == null
        ? null
        : _parseFontScaleRatio(ratio.toString());
    fontScaleRatio.value = normalized;
    if (normalized == null) {
      await _prefs.remove(_fontScaleKey);
    } else {
      await _prefs.setString(_fontScaleKey, normalized.toString());
    }
  }
}
