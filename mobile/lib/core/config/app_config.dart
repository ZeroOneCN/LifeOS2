/// 应用级常量与网络默认值。
abstract final class AppConfig {
  static const String appName = 'LifeOS';

  /// 默认指向局域网内的后端（9515），与网页端 9015 不同。
  ///
  /// 真机不能用 127.0.0.1（那是手机自己）；此值可在「设置 → 服务器地址」改。
  /// 后端契约前缀为 `/api/v1`（见 backend/app/core/config.py）。
  static const String defaultBaseUrl = 'http://192.168.8.103:9515/api/v1';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// 刷新令牌接口（后端：POST /auth/refresh，请求 {refresh_token}，
  /// 响应 {access_token, refresh_token, token_type}，每次轮换）。
  static const String refreshPath = '/auth/refresh';
}
