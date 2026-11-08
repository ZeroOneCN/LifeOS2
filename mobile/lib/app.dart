import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config/app_config.dart';
import 'theme/app_theme.dart';

class LifeOsApp extends StatelessWidget {
  const LifeOsApp({
    super.key,
    required this.router,
    required this.themeMode,
    required this.fontScaleRatio,
  });

  final GoRouter router;

  /// 由 `PreferencesService` 持有：设置页切换后立即重建，冷启动读回上次选择。
  final ValueNotifier<ThemeMode> themeMode;

  /// 全局字体缩放（相对系统）：`null` 表示跟随系统；首帧即生效，不闪。
  final ValueNotifier<double?> fontScaleRatio;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[themeMode, fontScaleRatio]),
      builder: (BuildContext context, Widget? _) {
        return MaterialApp.router(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode.value,
          routerConfig: router,
          // 字体缩放叠加在系统缩放之上：
          // 跟随系统时直接沿用原 `textScaler`，自定义档位则乘上比例。
          builder: (BuildContext context, Widget? child) {
            final double? ratio = fontScaleRatio.value;
            if (child == null || ratio == null) {
              return child ?? const SizedBox.shrink();
            }
            final MediaQueryData media = MediaQuery.of(context);
            final double systemFactor = media.textScaler.scale(1.0);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(systemFactor * ratio),
              ),
              child: child,
            );
          },
        );
      },
    );
  }
}
