import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/auth/auth_service.dart';
import '../../core/network/api_exception.dart';
import '../../theme/app_theme.dart';

/// 根页顶栏铃铛：显示真实未读数，点击进入通知中心。
///
/// 未读数取 `GET /notifications/stats?days=365`（后端无全局未读计数接口，
/// 这里以一年窗口近似）；请求失败时静默隐藏角标，不打断当前页面。
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;
  AuthService? _auth;

  @override
  void initState() {
    super.initState();
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    // 冷启动时 `restore()` 尚未返回，此时 isLoggedIn 为 false，
    // 因此订阅登录态，恢复成功后再拉未读数。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _auth = AppScope.of(context).auth;
      _auth!.addListener(_onAuthChanged);
      _loadUnread();
    });
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 登录态变化：恢复成功就补拉未读数；登出则清空角标。
  void _onAuthChanged() {
    if (!mounted) {
      return;
    }
    if (_auth!.isLoggedIn) {
      _loadUnread();
      return;
    }
    setState(() => _unread = 0);
  }

  /// 拉取未读数；失败保持上一次的值（首次为 0，不显示角标）。
  Future<void> _loadUnread() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      return;
    }
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/notifications/stats',
                queryParameters: <String, dynamic>{'days': 365},
              ))
          .data;
      if (!mounted) {
        return;
      }
      setState(() {
        _unread = (json?['unread'] as num?)?.toInt() ?? 0;
      });
    } on ApiException {
      // 角标是辅助信息，失败不提示；进入通知中心后回来会再次刷新。
    }
  }

  /// 进入通知中心；返回后刷新未读数（覆盖「标记已读 / 全部已读」的变化）。
  Future<void> _open() async {
    await context.push('/notifications');
    if (mounted) {
      _loadUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unread > 0 ? '通知（$_unread 条未读）' : '通知',
      onPressed: _open,
      // 角标只是数字装饰：排除其语义，避免读屏把按钮播报成「86」，
      // 完整信息由 tooltip 提供。
      icon: ExcludeSemantics(
        child: Badge.count(
          count: _unread,
          isLabelVisible: _unread > 0,
          backgroundColor: context.semanticColors.danger,
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }
}
