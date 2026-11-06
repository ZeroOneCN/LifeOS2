import 'package:flutter/material.dart' show ThemeMode, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 普通偏好存储（非敏感）：服务器地址、Tab 提示、离线队列等。
/// 敏感令牌不落这里，见 `TokenStore`（flutter_secure_storage）。
class PreferencesService {
  PreferencesService._(this._prefs);

  final SharedPreferences _prefs;

  static const String _baseUrlKey = 'server.base_url';
  static const String _tabHintKey = 'ui.tab_long_press_hint_shown';
  static const String _themeModeKey = 'ui.theme_mode';

  /// 全局主题模式：`MaterialApp` 监听它，设置页切换后立即生效并在冷启动恢复。
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  /// 创建实例；必须在 `runApp` 之前 await 完成。
  static Future<PreferencesService> create() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PreferencesService service = PreferencesService._(prefs);
    service.themeMode.value = _parseThemeMode(prefs.getString(_themeModeKey));
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

  /// 读取任意字符串键：离线队列等结构化数据以 JSON 字符串存储。
  String? readString(String key) => _prefs.getString(key);

  /// 写入任意字符串键。
  Future<void> writeString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  /// 读取任意布尔键。
  bool? readBool(String key) => _prefs.getBool(key);

  /// 写入任意布尔键。
  Future<void> writeBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  /// 当前服务器地址（含 `/api/v1` 前缀），未设置时回退默认值。
  String get baseUrl => _prefs.getString(_baseUrlKey) ?? AppConfig.defaultBaseUrl;

  /// 持久化服务器地址（由设置页校验、规范化后调用）。
  Future<void> setBaseUrl(String value) async {
    await _prefs.setString(_baseUrlKey, value);
  }

  /// 底部 Tab「长按看名称」的一次性提示是否已展示过。
  bool get tabHintShown => _prefs.getBool(_tabHintKey) ?? false;

  Future<void> markTabHintShown() async {
    await _prefs.setBool(_tabHintKey, true);
  }

  /// 切换深浅色：先更新内存（界面立刻生效），再落盘供下次冷启动读取。
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }
}
