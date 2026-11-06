import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'overview_models.dart';

/// 五域总览的加载状态。
///
/// - [idle]：尚未发起请求；
/// - [loading]：请求中且本地没有可用数据（页面显示加载态）；
/// - [ready]：有数据（刷新中仍保留旧数据，避免闪烁）；
/// - [unauthenticated]：没有令牌或会话已失效（引导去登录）；
/// - [connectionFailed]：有令牌但网络/服务不可达（保留登录态，给重试）；
/// - [failed]：单域请求失败（展示错误与重试）。
enum LoadStatus {
  idle,
  loading,
  ready,
  unauthenticated,
  connectionFailed,
  failed,
}

/// 单个域的总览状态：状态 + 数据 + 错误文案。
class OverviewState<T> {
  const OverviewState({this.status = LoadStatus.idle, this.data, this.message});

  final LoadStatus status;
  final T? data;
  final String? message;

  bool get isLoading => status == LoadStatus.loading;
  bool get hasData => data != null;
}

/// 总览数据控制器：登录后拉取四个业务域的总览，并随登录态自动刷新/清空。
///
/// 设计取舍：
/// - 只接「总览层」四个接口（health / finance / lifestyle / investment），
///   各业务列表页仍走占位，避免在 P2 铺开全部列表接口；
/// - **每个域一个 [ValueNotifier]**：五个 Tab 根页常驻在 IndexedStack 中，
///   若共用控制器的 `notifyListeners`，任一域返回数据都会把五个根页全部
///   重建一遍（含 IntrinsicHeight 网格），登录后四域并发完成时即表现为卡顿；
///   改为按域监听后，一次更新只重建当前域页面；
/// - 登录后**先拉可见 Tab（默认财务）**，其余三域随后并发，
///   避免四路请求 + JSON 解析在同一帧内互相挤占；
/// - 单域失败只影响该域状态，不阻塞其它四个 Tab；
/// - 令牌刷新由 `AuthInterceptor` 负责，这里只按 `ApiException` 分流状态。
class OverviewController extends ChangeNotifier {
  OverviewController(this._api, this._auth) {
    _lastLoggedIn = _auth.isLoggedIn;
    _lastConnectionFailed = _auth.connectionFailed;
    _auth.addListener(_handleAuthChange);
    _applyAuthState();
  }

  final ApiClient _api;
  final AuthService _auth;

  bool _lastLoggedIn = false;
  bool _lastConnectionFailed = false;
  bool _disposed = false;

  /// 各域独立监听源，供对应 Tab 根页订阅。
  final ValueNotifier<OverviewState<HealthOverview>> healthNotifier =
      ValueNotifier<OverviewState<HealthOverview>>(
    const OverviewState<HealthOverview>(),
  );
  final ValueNotifier<OverviewState<FinanceOverview>> financeNotifier =
      ValueNotifier<OverviewState<FinanceOverview>>(
    const OverviewState<FinanceOverview>(),
  );
  final ValueNotifier<OverviewState<LifestyleOverview>> lifestyleNotifier =
      ValueNotifier<OverviewState<LifestyleOverview>>(
    const OverviewState<LifestyleOverview>(),
  );
  final ValueNotifier<OverviewState<InvestmentOverview>> investmentNotifier =
      ValueNotifier<OverviewState<InvestmentOverview>>(
    const OverviewState<InvestmentOverview>(),
  );

  OverviewState<HealthOverview> get health => healthNotifier.value;
  OverviewState<FinanceOverview> get finance => financeNotifier.value;
  OverviewState<LifestyleOverview> get lifestyle => lifestyleNotifier.value;
  OverviewState<InvestmentOverview> get investment =>
      investmentNotifier.value;

  /// 同时刷新四域：先拉财务（默认落地页），其余三域随后并发。
  ///
  /// 实测（debug 构建，局域网后端）：四域同时发起时财务总览 490ms，
  /// 单路约 300ms；优先财务可让登录后首屏更快出数。
  Future<void> refreshAll() async {
    await refreshFinance();
    await Future.wait<void>(<Future<void>>[
      refreshHealth(),
      refreshLifestyle(),
      refreshInvestment(),
    ]);
  }

  Future<void> refreshHealth() => _load<HealthOverview>(
        path: '/health/overview',
        parse: HealthOverview.fromJson,
        notifier: healthNotifier,
      );

  Future<void> refreshFinance() => _load<FinanceOverview>(
        path: '/finance/overview',
        parse: FinanceOverview.fromJson,
        notifier: financeNotifier,
      );

  Future<void> refreshLifestyle() => _load<LifestyleOverview>(
        path: '/lifestyle/overview',
        parse: LifestyleOverview.fromJson,
        notifier: lifestyleNotifier,
      );

  Future<void> refreshInvestment() => _load<InvestmentOverview>(
        path: '/investment/overview',
        parse: InvestmentOverview.fromJson,
        notifier: investmentNotifier,
      );

  /// 状态条「重试」统一入口：
  /// - 连接失败 → 先重新恢复会话（网络恢复后即可拿到用户信息）；
  /// - 已登录 → 重新拉取四域；
  /// - 仍不可用 → 按当前原因回写状态（未登录 / 连接失败）。
  Future<void> retry() async {
    if (_auth.connectionFailed) {
      await _auth.restore();
    }
    if (_auth.isLoggedIn) {
      await refreshAll();
      return;
    }
    _applyAuthState();
  }

  Future<void> _load<T>({
    required String path,
    required T Function(Map<String, dynamic> json) parse,
    required ValueNotifier<OverviewState<T>> notifier,
  }) async {
    if (!_auth.isLoggedIn) {
      final bool offline = _auth.connectionFailed;
      _write<T>(
        notifier,
        OverviewState<T>(
          status: offline ? LoadStatus.connectionFailed : LoadStatus.unauthenticated,
          message: offline ? _auth.restoreError : null,
        ),
      );
      return;
    }

    final OverviewState<T> previous = notifier.value;
    _write<T>(
      notifier,
      OverviewState<T>(
        status: previous.hasData ? LoadStatus.ready : LoadStatus.loading,
        data: previous.data,
      ),
    );

    try {
      final Map<String, dynamic>? json =
          (await _api.get<Map<String, dynamic>>(path)).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '接口返回数据为空',
        );
      }
      _write<T>(notifier, OverviewState<T>(status: LoadStatus.ready, data: parse(json)));
    } on ApiException catch (error) {
      _write<T>(
        notifier,
        OverviewState<T>(
          status: error.isUnauthorized
              ? LoadStatus.unauthenticated
              : LoadStatus.failed,
          data: previous.data,
          message: error.message,
        ),
      );
    } catch (error) {
      _write<T>(
        notifier,
        OverviewState<T>(
          status: LoadStatus.failed,
          data: previous.data,
          message: '数据解析失败：$error',
        ),
      );
    }
  }

  /// 写入单域状态：先更新域监听源，再通知聚合监听（设置页状态行）。
  void _write<T>(
    ValueNotifier<OverviewState<T>> notifier,
    OverviewState<T> value,
  ) {
    notifier.value = value;
    notifyListeners();
  }

  void _handleAuthChange() {
    final bool loggedIn = _auth.isLoggedIn;
    final bool connectionFailed = _auth.connectionFailed;
    if (loggedIn == _lastLoggedIn && connectionFailed == _lastConnectionFailed) {
      return;
    }
    _lastLoggedIn = loggedIn;
    _lastConnectionFailed = connectionFailed;
    if (loggedIn) {
      unawaited(refreshAll());
    } else {
      _applyAuthState();
    }
  }

  /// 按登录态回写四域的统一状态（未登录 / 连接失败）。
  void _applyAuthState() {
    if (_auth.isLoggedIn) {
      unawaited(refreshAll());
      return;
    }
    if (_auth.connectionFailed) {
      _setAll(
        LoadStatus.connectionFailed,
        _auth.restoreError ?? '无法连接服务器',
      );
      return;
    }
    _setAll(LoadStatus.unauthenticated, null);
  }

  void _setAll(LoadStatus status, String? message) {
    healthNotifier.value = OverviewState<HealthOverview>(
      status: status,
      message: message,
    );
    financeNotifier.value = OverviewState<FinanceOverview>(
      status: status,
      message: message,
    );
    lifestyleNotifier.value = OverviewState<LifestyleOverview>(
      status: status,
      message: message,
    );
    investmentNotifier.value = OverviewState<InvestmentOverview>(
      status: status,
      message: message,
    );
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_handleAuthChange);
    healthNotifier.dispose();
    financeNotifier.dispose();
    lifestyleNotifier.dispose();
    investmentNotifier.dispose();
    super.dispose();
  }
}
