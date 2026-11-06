import 'package:dio/dio.dart';

/// 统一错误模型：所有页面只处理 ApiException，不直接接触 DioException。
enum ApiErrorKind {
  /// 无网络 / DNS / 连接被拒
  network,

  /// 连接、发送、接收超时
  timeout,

  /// 401，刷新失败或未登录
  unauthorized,

  /// 403
  forbidden,

  /// 404
  notFound,

  /// 5xx
  server,

  /// 证书校验失败（自签 HTTPS 场景）
  badCertificate,

  /// 其他 4xx / 响应格式异常
  badResponse,

  /// 请求被取消
  cancelled,

  /// 未知
  unknown,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  /// 后端业务错误码（若接口返回 `code` 字段）
  final String? code;

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  @override
  String toString() =>
      'ApiException(kind: $kind, statusCode: $statusCode, message: $message)';

  /// 把 Dio 异常归一化为业务可读错误。
  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          kind: ApiErrorKind.timeout,
          message: '连接超时，请检查服务器地址与网络',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          kind: ApiErrorKind.network,
          message: '无法连接服务器，请检查地址、端口与局域网',
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          kind: ApiErrorKind.badCertificate,
          message: '服务器证书校验失败',
        );
      case DioExceptionType.cancel:
        return const ApiException(
          kind: ApiErrorKind.cancelled,
          message: '请求已取消',
        );
      case DioExceptionType.badResponse:
        final int? status = error.response?.statusCode;
        final String? serverMessage = _extractMessage(error.response?.data);
        final ApiErrorKind kind;
        if (status == 401) {
          kind = ApiErrorKind.unauthorized;
        } else if (status == 403) {
          kind = ApiErrorKind.forbidden;
        } else if (status == 404) {
          kind = ApiErrorKind.notFound;
        } else if (status != null && status >= 500) {
          kind = ApiErrorKind.server;
        } else {
          kind = ApiErrorKind.badResponse;
        }
        return ApiException(
          kind: kind,
          statusCode: status,
          message: serverMessage ?? _defaultMessage(kind),
        );
      case DioExceptionType.unknown:
        return ApiException(
          kind: ApiErrorKind.unknown,
          message: error.message ?? '请求失败，请稍后重试',
        );
    }
  }

  static String _defaultMessage(ApiErrorKind kind) {
    switch (kind) {
      case ApiErrorKind.unauthorized:
        return '登录状态已失效，请重新登录';
      case ApiErrorKind.forbidden:
        return '没有权限执行该操作';
      case ApiErrorKind.notFound:
        return '接口不存在（404）';
      case ApiErrorKind.server:
        return '服务器内部错误，请稍后重试';
      default:
        return '请求失败，请稍后重试';
    }
  }

  /// FastAPI 的错误体通常是 `{"detail": "..."}`，也兼容 `{"message": "..."}`。
  static String? _extractMessage(dynamic data) {
    if (data is Map) {
      final dynamic detail = data['detail'] ?? data['message'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
    }
    return null;
  }
}
