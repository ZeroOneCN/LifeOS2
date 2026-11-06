import 'package:flutter/widgets.dart';

import 'auth/auth_service.dart';
import 'data/overview_controller.dart';
import 'network/api_client.dart';
import 'profile/profile_service.dart';
import 'storage/preferences_service.dart';
import 'storage/token_store.dart';

/// 轻量依赖注入：P2 仍不引入 Provider / Riverpod，
/// 用一个 InheritedWidget 把「偏好 + 令牌 + ApiClient + 登录态 + 总览」传给整棵树。
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.preferences,
    required this.tokenStore,
    required this.apiClient,
    required this.auth,
    required this.overview,
    required this.profile,
    required super.child,
  });

  final PreferencesService preferences;
  final TokenStore tokenStore;
  final ApiClient apiClient;

  /// 登录态中心：登录 / 恢复会话 / 登出。
  final AuthService auth;

  /// 四域总览数据：随登录态自动刷新，页面用 ListenableBuilder 订阅。
  final OverviewController overview;

  /// 头像上传 / 外链设置（契约见 ProfileService）。
  final ProfileService profile;

  static AppScope of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载：请确认 main.dart 用 AppScope 包裹 LifeOsApp');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return preferences != oldWidget.preferences ||
        tokenStore != oldWidget.tokenStore ||
        apiClient != oldWidget.apiClient ||
        auth != oldWidget.auth ||
        overview != oldWidget.overview ||
        profile != oldWidget.profile;
  }
}

