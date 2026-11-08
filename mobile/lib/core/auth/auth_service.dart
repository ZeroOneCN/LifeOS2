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

  /// 本地是否存有令牌（冷启动读盘后置真）。
  ///
  /// 与 [isLoggedIn] 区分：有令牌但 `/auth/me` 因网络不可达而失败时，
  /// 用户仍处于「已保留登录状态」，不应该被踢回登录页。
  bool _hasLocalSession = false;
  bool get hasLocalSession => _hasLocalSession;

  /// 冷启动恢复时是否因网络/服务不可达而失败（区别于 401 失效）。
  bool _connectionFailed = false;
  bool get connectionFailed => _connectionFailed;

  /// 连接失败的具体原因，供状态条展示。
  String? _restoreError;
  String? get restoreError => _restoreError;

  /// 冷启动恢复：有令牌则拉取 `/auth/me`。
  ///
  /// access 过期时由拦截器自动刷新并重放（`/auth/me` 不跳过刷新），
  /// 刷新失败会清空令牌并回调 [handleSessionExpired]。
  ///
  /// 失败分流：
  /// - 401（会话真失效）→ 清空令牌，回到「未登录」；
  /// - 网络/超时/5xx → 保留令牌，标记 [connectionFailed]，供 UI 显示重试。
  Future<void> restore() async {
    final String? access = await _tokenStore.readAccessToken();
    if (access == null || access.isEmpty) {
      _hasLocalSession = false;
      return;
    }
    _hasLocalSession = true;
    try {
      final Map<String, dynamic>? data = (await _api.get<Map<String, dynamic>>(
        '/auth/me',
      ))
          .data;
      if (data != null) {
        _user = AppUser.fromJson(data);
        _connectionFailed = false;
        _restoreError = null;
        notifyListeners();
      }
    } on ApiException catch (error) {
      _user = null;
      if (error.isUnauthorized) {
        await _tokenStore.clear();
        _hasLocalSession = false;
        _connectionFailed = false;
        _restoreError = null;
      } else {
        _connectionFailed = true;
        _restoreError = error.message;
      }
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
    _hasLocalSession = true;
    _connectionFailed = false;
    _restoreError = null;
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
    _hasLocalSession = false;
    _connectionFailed = false;
    _restoreError = null;
    notifyListeners();
  }

  /// 下线除当前设备外的所有登录会话。
  ///
  /// 后端 `POST /auth/sessions/revoke-others` 以 refresh_token 识别「当前会话」，
  /// 只删除其余会话，因此不会把本机踢下线。返回被清理的会话数量由列表刷新体现。
  Future<void> revokeOtherSessions() async {
    final String? refresh = await _tokenStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.unauthorized,
        message: '本地没有可用的刷新令牌，请重新登录',
      );
    }
    await _api.post<void>(
      '/auth/sessions/revoke-others',
      data: <String, dynamic>{'refresh_token': refresh},
    );
  }

  /// 用 `/user/profile` 刷新账号资料（头像等），成功后通知所有订阅者。
  ///
  /// 兼容两种响应：`{...用户字段}` 或 `{ "user": {...} }`。
  ///
  /// 该接口只返回资料字段（不含 `account` / `is_admin`），因此要与当前
  /// [user] 合并而不是整体替换，否则登录状态行会显示成「已登录（）」；
  /// `avatar: null`（移除头像）要能真正覆盖旧值，所以这里用展开覆盖语义。
  Future<void> refreshProfile() async {
    final Map<String, dynamic>? data =
        (await _api.get<Map<String, dynamic>>('/user/profile')).data;
    if (data == null) {
      return;
    }
    final Map<String, dynamic> json =
        (data['user'] as Map?)?.cast<String, dynamic>() ?? data;
    final AppUser? current = _user;
    _user = AppUser.fromJson(<String, dynamic>{
      if (current != null) ...<String, dynamic>{
        'account': current.account,
        'is_admin': current.isAdmin,
        'username': current.username,
      },
      ...json,
    });
    notifyListeners();
  }

  /// 由 `ApiClient` 在刷新失败时回调：令牌已被拦截器清空，这里只更新 UI 状态。
  void handleSessionExpired() {
    _hasLocalSession = false;
    _connectionFailed = false;
    _restoreError = null;
    if (_user == null) {
      return;
    }
    _user = null;
    notifyListeners();
  }
}
