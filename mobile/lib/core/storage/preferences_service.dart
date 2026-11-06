import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 普通偏好存储（非敏感）：目前只有服务器地址。
/// 敏感令牌不落这里，见 `TokenStore`（flutter_secure_storage）。
class PreferencesService {
  PreferencesService._(this._prefs);

  final SharedPreferences _prefs;

  static const String _baseUrlKey = 'server.base_url';
  static const String _tabHintKey = 'ui.tab_long_press_hint_shown';

  /// 创建实例；必须在 `runApp` 之前 await 完成。
  static Future<PreferencesService> create() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return PreferencesService._(prefs);
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
}
