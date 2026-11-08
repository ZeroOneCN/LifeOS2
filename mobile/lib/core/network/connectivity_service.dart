import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 连通性状态：只回答「当前有没有网络」。
///
/// 离线队列下线后，写操作全部改为直接请求；本服务仅用于保存前做一次
/// 快速提示（真正成功与否仍以接口返回为准，网络错误与服务端错误分开提示）。
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;

  /// 当前是否联网。
  bool get isOnline => _online;

  /// 读取初始连通性并订阅变化。
  Future<void> init() async {
    try {
      _online = _hasNetwork(await _connectivity.checkConnectivity());
    } catch (_) {
      // 取不到连通性时不拦写操作，交给接口错误提示。
      _online = true;
    }
    _subscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final bool online = _hasNetwork(results);
      if (online == _online) {
        return;
      }
      _online = online;
      notifyListeners();
    });
  }

  static bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any(
      (ConnectivityResult item) => item != ConnectivityResult.none,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
