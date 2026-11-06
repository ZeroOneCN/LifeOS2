import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 令牌存储：access / refresh 都进 Android Keystore 支持的加密存储。
///
/// 注意：后端 refresh token 每次刷新都会轮换（滑动续期 365 天），
/// 因此刷新成功后必须把**新的 refresh token 同步落盘**，否则下次刷新会 401。
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _accessKey = 'auth.access_token';
  static const String _refreshKey = 'auth.refresh_token';

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  /// 同时写入两枚令牌（登录 / 刷新轮换成功后调用）。
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  /// 登出 / 刷新失败时清空本地会话。
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
