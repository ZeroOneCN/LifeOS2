import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

/// 全局未读通知数：五个 Tab 根页的铃铛共用一个数据源。
///
/// 每个根页各自 new 一个铃铛会导致「在通知中心读掉几条后，切到另一个 Tab
/// 铃铛还停在旧值」；这里把计数上移，任何页面读走/标记已读后，
/// 所有铃铛立即同步。
///
/// 后端没有全局未读接口，用 `GET /notifications/stats?days=365` 近似。
class NotificationUnreadController extends ChangeNotifier {
  NotificationUnreadController(this._api, this._auth) {
    _auth.addListener(_onAuthChanged);
    if (_auth.isLoggedIn) {
      refresh();
    }
  }

  final ApiClient _api;
  final AuthService _auth;

  int _count = 0;
  bool _loading = false;

  /// 当前未读条数。
  int get count => _count;

  bool get loading => _loading;

  /// 登录态变化：登录后拉取，登出清零。
  void _onAuthChanged() {
    if (_auth.isLoggedIn) {
      refresh();
      return;
    }
    setCount(0);
  }

  /// 以服务端为准刷新未读数；失败静默保留旧值（角标是辅助信息）。
  Future<void> refresh() async {
    if (!_auth.isLoggedIn || _loading) {
      return;
    }
    _loading = true;
    try {
      final Map<String, dynamic>? json = (await _api
              .get<Map<String, dynamic>>(
                '/notifications/stats',
                queryParameters: <String, dynamic>{'days': 365},
              ))
          .data;
      final int unread = (json?['unread'] as num?)?.toInt() ?? 0;
      _loading = false;
      setCount(unread);
    } on ApiException {
      _loading = false;
    }
  }

  /// 通知中心本地已读后直接下发新值，避免再发一次请求才更新角标。
  void setCount(int value) {
    final int next = value < 0 ? 0 : value;
    if (next == _count) {
      return;
    }
    _count = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
