import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/auth/auth_service.dart';
import 'core/data/notification_unread_controller.dart';
import 'core/data/overview_controller.dart';
import 'core/network/api_client.dart';
import 'core/network/connectivity_service.dart';
import 'core/profile/profile_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/preferences_service.dart';
import 'core/storage/token_store.dart';
import 'core/update/update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 竖屏锁定（手机端）。Android 16 在 ≥600dp 大屏会忽略方向锁定，
  // 大屏/横屏适配留到 P2，不在这里硬做。
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  final PreferencesService preferences = await PreferencesService.create();
  final TokenStore tokenStore = TokenStore();

  late final AuthService authService;
  final ApiClient apiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: preferences.baseUrl,
    onSessionExpired: () => authService.handleSessionExpired(),
  );
  authService = AuthService(apiClient, tokenStore);
  final OverviewController overview = OverviewController(
    apiClient,
    authService,
  );
  final NotificationUnreadController notifications =
      NotificationUnreadController(apiClient, authService);
  final ProfileService profile = ProfileService(apiClient, authService);
  final ConnectivityService connectivity = ConnectivityService();
  // 先取一次连通性，保证首屏的「无网络」提示准确。
  await connectivity.init();
  // 版本信息必须在首帧前拿到：关于页与更新标记都依赖当前构建号。
  final UpdateController update = UpdateController(
    preferences: preferences,
    apiClient: apiClient,
  );
  await update.init();

  runApp(
    AppScope(
      preferences: preferences,
      tokenStore: tokenStore,
      apiClient: apiClient,
      auth: authService,
      overview: overview,
      notifications: notifications,
      profile: profile,
      connectivity: connectivity,
      update: update,
      child: LifeOsApp(router: createAppRouter()),
    ),
  );

  // 冷启动恢复：有令牌则拉 /auth/me；恢复成功后由 OverviewController
  // 监听到登录态变化自动拉四个总览。
  unawaited(authService.restore());
  // 启动时静默检查更新：不弹窗、失败不打扰，只有发现新版才在当前会话里亮标记。
  unawaited(update.checkSilently());
}
