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

  /// 服务端 Origin（含协议/主机/端口，去掉 `/api/v1` 路径）。
  ///
  /// 后端返回的上传头像形如 `/api/v1/uploads/avatars/xxx.png`，
  /// 移动端需要拼上 Origin 才能加载。
  String get origin => Uri.parse(baseUrl).origin;

  /// 把头像字段解析成可加载的绝对地址：
  /// - `null` / 空串 → null（走占位头像）；
  /// - 以 `/` 开头 → 拼 [origin]；
  /// - 以 `http` 开头 → 原样使用。
  String? resolveAvatar(String? avatar) {
    final String? value = avatar?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.startsWith('/')) {
      return '$origin$value';
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return null;
  }

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

  /// POST 请求；[onReceiveProgress] 供大文件下载（备份导出）显示接收进度。
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    ProgressCallback? onReceiveProgress,
  }) {
    return _guard(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        onReceiveProgress: onReceiveProgress,
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

  /// PATCH 请求：用于只更新部分字段（如通知批量接口只提交 `read`）。
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _guard(
      () => _dio.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  /// multipart 上传（头像 / Excel 导入），支持发送进度回调。
  Future<Response<T>> postMultipart<T>(
    String path, {
    required FormData data,
    Map<String, dynamic>? queryParameters,
    ProgressCallback? onSendProgress,
  }) {
    return _guard(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        onSendProgress: onSendProgress,
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
