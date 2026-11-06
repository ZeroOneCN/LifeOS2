import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/token_store.dart';

/// 登录态中心：负责登录、恢复会话、登出，并在失效时清空本地令牌。
///
/// 令牌落盘规则（与后端 `auth.py` 对齐）：
/// - 登录响应一次性写入 access + refresh；
/// - 刷新由 `AuthInterceptor` 单飞处理，轮换后的 refresh 由拦截器同步落盘；
/// - 本服务只负责在恢复/登出时读写，不重复实现刷新逻辑。
class AuthService extends ChangeNotifier {
  AuthService(this._api, this._tokenStore);

  final ApiClient _api;
  final TokenStore _tokenStore;

  AppUser? _user;
  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;

  /// 冷启动恢复：有令牌则拉取 `/auth/me`。
  ///
  /// access 过期时由拦截器自动刷新并重放（`/auth/me` 不跳过刷新），
  /// 刷新失败会清空令牌并回调 [handleSessionExpired]。
  Future<void> restore() async {
    final String? access = await _tokenStore.readAccessToken();
    if (access == null || access.isEmpty) {
      return;
    }
    try {
      final Map<String, dynamic>? data = (await _api.get<Map<String, dynamic>>(
        '/auth/me',
      ))
          .data;
      if (data != null) {
        _user = AppUser.fromJson(data);
        notifyListeners();
      }
    } on ApiException {
      _user = null;
      notifyListeners();
    }
  }

  /// 账号密码登录；令牌与用户信息同时落盘/更新。
  Future<void> login({
    required String account,
    required String password,
  }) async {
    final Map<String, dynamic>? data = (await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: <String, dynamic>{'account': account, 'password': password},
    ))
        .data;
    if (data == null) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '登录响应为空，请检查服务器地址',
      );
    }
    final String? access = data['access_token'] as String?;
    final String? refresh = data['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '登录响应缺少令牌字段',
      );
    }
    await _tokenStore.saveTokens(accessToken: access, refreshToken: refresh);
    final Map<String, dynamic>? userJson =
        (data['user'] as Map?)?.cast<String, dynamic>();
    _user = userJson == null ? null : AppUser.fromJson(userJson);
    notifyListeners();
  }

  /// 登出：先尽力通知后端删除会话，再清本地令牌（离线也能登出）。
  Future<void> logout() async {
    try {
      final String? refresh = await _tokenStore.readRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        await _api.post<void>(
          '/auth/logout',
          data: <String, dynamic>{'refresh_token': refresh},
        );
      }
    } on ApiException {
      // 离线或会话已失效都不阻塞本地登出
    }
    await _tokenStore.clear();
    _user = null;
    notifyListeners();
  }

  /// 由 `ApiClient` 在刷新失败时回调：令牌已被拦截器清空，这里只更新 UI 状态。
  void handleSessionExpired() {
    if (_user == null) {
      return;
    }
    _user = null;
    notifyListeners();
  }
}
