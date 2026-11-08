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
    // 只有主题切换才重建 `MaterialApp`；字体缩放放在 `builder` 内部单独监听，
    // 避免每次调节字号都重建 MaterialApp / Router（那会连带重建全部 Tab 分支，
    // 也是之前切换字号时卡顿的主要原因）。
    return ListenableBuilder(
      listenable: themeMode,
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
            if (child == null) {
              return const SizedBox.shrink();
            }
            return ValueListenableBuilder<double?>(
              valueListenable: fontScaleRatio,
              // child 传下去，切换字号时不重建页面树，只替换 MediaQuery。
              child: child,
              builder: (BuildContext context, double? ratio, Widget? scaled) {
                final Widget page = scaled ?? const SizedBox.shrink();
                if (ratio == null) {
                  return page;
                }
                final MediaQueryData media = MediaQuery.of(context);
                final double systemFactor = media.textScaler.scale(1.0);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(systemFactor * ratio),
                  ),
                  child: page,
                );
              },
            );
          },
        );
      },
    );
  }
}
