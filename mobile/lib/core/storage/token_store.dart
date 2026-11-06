import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 令牌存储：access / refresh 都进 Android Keystore 支持的加密存储。
///
/// 注意：后端 refresh token 每次刷新都会轮换（滑动续期 365 天），
/// 因此刷新成功后必须把**新的 refresh token 同步落盘**，否则下次刷新会 401。
///
/// 性能取舍：每个业务请求的拦截器都要读一次 access token，如果每次都走
/// platform channel，会为每个请求额外增加一次跨端往返（实测约 10–15ms）。
/// 这里加一层内存缓存：首次读盘后驻留内存，写入/清空时同步更新缓存，
/// 请求侧不再产生额外的跨端阻塞。
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _accessKey = 'auth.access_token';
  static const String _refreshKey = 'auth.refresh_token';

  String? _cachedAccess;
  String? _cachedRefresh;
  bool _accessLoaded = false;
  bool _refreshLoaded = false;

  Future<String?> readAccessToken() async {
    if (_accessLoaded) {
      return _cachedAccess;
    }
    final String? value = await _storage.read(key: _accessKey);
    _cachedAccess = value;
    _accessLoaded = true;
    return value;
  }

  Future<String?> readRefreshToken() async {
    if (_refreshLoaded) {
      return _cachedRefresh;
    }
    final String? value = await _storage.read(key: _refreshKey);
    _cachedRefresh = value;
    _refreshLoaded = true;
    return value;
  }

  /// 同时写入两枚令牌（登录 / 刷新轮换成功后调用）。
  ///
  /// 先更新内存缓存再并行落盘：调用方随后的请求可立即拿到新令牌，
  /// 同时两枚令牌的写入不再串行等待。
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _cachedAccess = accessToken;
    _cachedRefresh = refreshToken;
    _accessLoaded = true;
    _refreshLoaded = true;
    await Future.wait<void>(<Future<void>>[
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
    ]);
  }

  /// 登出 / 刷新失败时清空本地会话。
  Future<void> clear() async {
    _cachedAccess = null;
    _cachedRefresh = null;
    _accessLoaded = true;
    _refreshLoaded = true;
    await Future.wait<void>(<Future<void>>[
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
