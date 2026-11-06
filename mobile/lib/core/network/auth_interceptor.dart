import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';

/// 认证拦截器：注入 Bearer、401 单飞刷新、刷新令牌轮换落盘。
///
/// 关键约束（与后端 `backend/app/api/routes/auth.py` 对齐）：
/// - `POST /auth/refresh` 请求体 `{refresh_token}`；
/// - 响应 `{access_token, refresh_token, token_type}`，**refresh 每次轮换**；
/// - 新的 refresh 必须立即写入安全存储，否则下次刷新直接 401。
class AuthInterceptor extends Interceptor {
  AuthInterceptor(
    this._tokenStore,
    this._refreshDio,
    this._retryDio, {
    VoidCallback? onSessionExpired,
  }) : _onSessionExpired = onSessionExpired ?? _defaultSessionExpired;

  final TokenStore _tokenStore;
  final Dio _refreshDio;
  final Dio _retryDio;
  final VoidCallback _onSessionExpired;

  /// 单飞：并发多个 401 只发起一次刷新。
  Future<String?>? _refreshInFlight;

  static const String _retriedFlag = 'auth.retried';
  static const String _skipRefreshFlag = 'auth.skip_refresh';

  /// 这些接口本身不参与「401 刷新重放」，否则会用新 access 去重放登录/刷新请求。
  ///
  /// 注意 `/auth/me` **不在**列表内：冷启动 access 过期时必须先刷新再重放，
  /// 否则会误判成未登录。
  static const List<String> _noRefreshPaths = <String>[
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/logout',
  ];

  static void _defaultSessionExpired() {
    debugPrint('[auth] 会话已失效，令牌已清空');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _attachToken(options, handler);
  }

  Future<void> _attachToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final String? access = await _tokenStore.readAccessToken();
      if (access != null && access.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    } catch (error) {
      debugPrint('[auth] 读取 access token 失败：$error');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _handleError(err, handler);
  }

  Future<void> _handleError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int? status = err.response?.statusCode;
    final bool retried = err.requestOptions.extra[_retriedFlag] == true;
    final bool authEndpoint =
        _noRefreshPaths.any(err.requestOptions.path.contains) ||
        err.requestOptions.extra[_skipRefreshFlag] == true;

    // 只对「非认证接口的首次 401」做刷新重放
    if (status != 401 || retried || authEndpoint) {
      handler.next(err);
      return;
    }

    try {
      final String? access = await _refreshSingleFlight();
      if (access == null) {
        await _tokenStore.clear();
        _onSessionExpired();
        handler.next(err);
        return;
      }
      final RequestOptions retryOptions = err.requestOptions
        ..extra[_retriedFlag] = true;
      retryOptions.headers['Authorization'] = 'Bearer $access';
      handler.resolve(await _retryDio.fetch<dynamic>(retryOptions));
    } catch (error) {
      debugPrint('[auth] 刷新后重放失败：$error');
      handler.next(err);
    }
  }

  Future<String?> _refreshSingleFlight() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _doRefresh() async {
    final String? refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    final Response<dynamic> response = await _refreshDio.post<dynamic>(
      AppConfig.refreshPath,
      data: <String, dynamic>{'refresh_token': refreshToken},
    );
    final dynamic data = response.data;
    if (data is! Map) {
      return null;
    }
    final dynamic access = data['access_token'];
    final dynamic newRefresh = data['refresh_token'];
    if (access is! String || newRefresh is! String) {
      return null;
    }
    // 轮换必须落盘：两枚令牌一起覆盖
    await _tokenStore.saveTokens(
      accessToken: access,
      refreshToken: newRefresh,
    );
    return access;
  }
}
