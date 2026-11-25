import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 普通偏好存储（非敏感）：服务器地址、更新地址。
/// 敏感令牌不落这里，见 `TokenStore`（flutter_secure_storage）。
///
/// 外观与字体大小不再由应用接管：主题固定跟随系统，字号沿用系统缩放。
class PreferencesService {
  PreferencesService._(this._prefs);

  final SharedPreferences _prefs;

  static const String _baseUrlKey = 'server.base_url';
  static const String _updateBaseUrlKey = 'update.base_url';

  /// 创建实例；必须在 `runApp` 之前 await 完成。
  static Future<PreferencesService> create() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return PreferencesService._(prefs);
  }

  /// 当前服务器地址（含 `/api/v1` 前缀），未设置时回退默认值。
  String get baseUrl =>
      _prefs.getString(_baseUrlKey) ?? AppConfig.defaultBaseUrl;

  /// 持久化服务器地址（由设置页校验、规范化后调用）。
  Future<void> setBaseUrl(String value) async {
    await _prefs.setString(_baseUrlKey, value);
  }

  /// 检查更新用的服务器根地址（形如 `http://192.168.8.103:9515`，不含 `/api/v1`）。
  ///
  /// 返回 null 表示「跟随当前 API 地址的 host」——局域网 IP 变了只改一处即可。
  String? get updateBaseUrl {
    final String? value = _prefs.getString(_updateBaseUrlKey);
    return (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  /// 持久化更新服务器地址；传 null 或空串表示恢复跟随 API 地址。
  Future<void> setUpdateBaseUrl(String? value) async {
    final String normalized = (value ?? '').trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (normalized.isEmpty) {
      await _prefs.remove(_updateBaseUrlKey);
    } else {
      await _prefs.setString(_updateBaseUrlKey, normalized);
    }
  }
}
