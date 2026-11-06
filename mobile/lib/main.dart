import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/auth/auth_service.dart';
import 'core/data/overview_controller.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/storage/preferences_service.dart';
import 'core/storage/token_store.dart';

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
  final OverviewController overview = OverviewController(apiClient, authService);

  runApp(
    AppScope(
      preferences: preferences,
      tokenStore: tokenStore,
      apiClient: apiClient,
      auth: authService,
      overview: overview,
      child: LifeOsApp(router: createAppRouter()),
    ),
  );

  // 冷启动恢复：有令牌则拉 /auth/me；恢复成功后由 OverviewController
  // 监听到登录态变化自动拉四个总览。
  unawaited(authService.restore());
}

