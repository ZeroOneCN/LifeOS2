import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config/app_config.dart';
import 'theme/app_theme.dart';

/// 应用根组件：主题固定跟随系统，字号沿用系统缩放，不再提供应用内覆盖。
class LifeOsApp extends StatelessWidget {
  const LifeOsApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      // 跟随系统字号，但把上限收在 1.3：更极端的系统字号会让三列指标卡
      // 与金额行整体溢出；需要更大字号时靠组件内的等比缩放兜底。
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
