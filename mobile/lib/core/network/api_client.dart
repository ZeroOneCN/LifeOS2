import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// 统一 HTTP 入口。
///
/// P1 只搭骨架、不接真实业务接口：
/// - 所有请求经 `_dio`，自动带 Bearer、401 单飞刷新；
/// - 页面只捕获 `ApiException`；
/// - 服务器地址可在设置页修改，改后立即更新两个 Dio 实例。
class ApiClient {
  ApiClient({
    required TokenStore tokenStore,
    required String baseUrl,
    VoidCallback? onSessionExpired,
  })  : _baseUrlNotifier = ValueNotifier<String>(_normalize(baseUrl)),
        _dio = Dio(_options(_normalize(baseUrl))),
        _refreshDio = Dio(_options(_normalize(baseUrl))) {
    _dio.interceptors.add(
      AuthInterceptor(
        tokenStore,
        _refreshDio,
        _dio,
        onSessionExpired: onSessionExpired,
      ),
    );
  }

  final Dio _dio;
  final Dio _refreshDio;
  final ValueNotifier<String> _baseUrlNotifier;

  /// 供设置页监听地址变化（ValueListenableBuilder）。
  ValueListenable<String> get baseUrlListenable => _baseUrlNotifier;

  String get baseUrl => _dio.options.baseUrl;

  /// 修改服务器地址：去尾斜杠、同步两个 Dio、通知 UI。
  void updateBaseUrl(String value) {
    final String normalized = _normalize(value);
    _dio.options.baseUrl = normalized;
    _refreshDio.options.baseUrl = normalized;
    _baseUrlNotifier.value = normalized;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  /// 统一异常归一化：DioException → ApiException。
  Future<Response<T>> _guard<T>(
    Future<Response<T>> Function() run,
  ) async {
    try {
      return await run();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  static BaseOptions _options(String baseUrl) {
    return BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      sendTimeout: AppConfig.sendTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: const <String, dynamic>{'Accept': 'application/json'},
      responseType: ResponseType.json,
    );
  }

  static String _normalize(String value) {
    final String trimmed = value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
