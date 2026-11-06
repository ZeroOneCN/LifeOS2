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
/// - [unauthenticated]：未登录或会话失效（引导去登录）；
/// - [failed]：请求失败（展示错误与重试）。
enum LoadStatus { idle, loading, ready, unauthenticated, failed }

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
/// - 单域失败只影响该域状态，不阻塞其它四个 Tab；
/// - 令牌刷新由 `AuthInterceptor` 负责，这里只按 `ApiException` 分流状态。
class OverviewController extends ChangeNotifier {
  OverviewController(this._api, this._auth) {
    _lastLoggedIn = _auth.isLoggedIn;
    _auth.addListener(_handleAuthChange);
    if (_lastLoggedIn) {
      unawaited(refreshAll());
    } else {
      _setUnauthenticated();
    }
  }

  final ApiClient _api;
  final AuthService _auth;

  bool _lastLoggedIn = false;
  bool _disposed = false;

  OverviewState<HealthOverview> _health = const OverviewState<HealthOverview>();
  OverviewState<FinanceOverview> _finance =
      const OverviewState<FinanceOverview>();
  OverviewState<LifestyleOverview> _lifestyle =
      const OverviewState<LifestyleOverview>();
  OverviewState<InvestmentOverview> _investment =
      const OverviewState<InvestmentOverview>();

  OverviewState<HealthOverview> get health => _health;
  OverviewState<FinanceOverview> get finance => _finance;
  OverviewState<LifestyleOverview> get lifestyle => _lifestyle;
  OverviewState<InvestmentOverview> get investment => _investment;

  /// 同时刷新四域；返回的 Future 在四域都结束后完成。
  Future<void> refreshAll() {
    return Future.wait<void>(<Future<void>>[
      refreshHealth(),
      refreshFinance(),
      refreshLifestyle(),
      refreshInvestment(),
    ]);
  }

  Future<void> refreshHealth() => _load<HealthOverview>(
        path: '/health/overview',
        parse: HealthOverview.fromJson,
        read: () => _health,
        write: (OverviewState<HealthOverview> value) => _health = value,
      );

  Future<void> refreshFinance() => _load<FinanceOverview>(
        path: '/finance/overview',
        parse: FinanceOverview.fromJson,
        read: () => _finance,
        write: (OverviewState<FinanceOverview> value) => _finance = value,
      );

  Future<void> refreshLifestyle() => _load<LifestyleOverview>(
        path: '/lifestyle/overview',
        parse: LifestyleOverview.fromJson,
        read: () => _lifestyle,
        write: (OverviewState<LifestyleOverview> value) => _lifestyle = value,
      );

  Future<void> refreshInvestment() => _load<InvestmentOverview>(
        path: '/investment/overview',
        parse: InvestmentOverview.fromJson,
        read: () => _investment,
        write: (OverviewState<InvestmentOverview> value) =>
            _investment = value,
      );

  Future<void> _load<T>({
    required String path,
    required T Function(Map<String, dynamic> json) parse,
    required OverviewState<T> Function() read,
    required void Function(OverviewState<T> value) write,
  }) async {
    if (!_auth.isLoggedIn) {
      write(OverviewState<T>(status: LoadStatus.unauthenticated));
      notifyListeners();
      return;
    }

    final OverviewState<T> previous = read();
    write(
      OverviewState<T>(
        status: previous.hasData ? LoadStatus.ready : LoadStatus.loading,
        data: previous.data,
      ),
    );
    notifyListeners();

    try {
      final Map<String, dynamic>? json =
          (await _api.get<Map<String, dynamic>>(path)).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '接口返回数据为空',
        );
      }
      write(OverviewState<T>(status: LoadStatus.ready, data: parse(json)));
    } on ApiException catch (error) {
      write(
        OverviewState<T>(
          status: error.isUnauthorized
              ? LoadStatus.unauthenticated
              : LoadStatus.failed,
          data: previous.data,
          message: error.message,
        ),
      );
    } catch (error) {
      write(
        OverviewState<T>(
          status: LoadStatus.failed,
          data: previous.data,
          message: '数据解析失败：$error',
        ),
      );
    }
    notifyListeners();
  }

  void _handleAuthChange() {
    final bool loggedIn = _auth.isLoggedIn;
    if (loggedIn == _lastLoggedIn) {
      return;
    }
    _lastLoggedIn = loggedIn;
    if (loggedIn) {
      unawaited(refreshAll());
    } else {
      _setUnauthenticated();
    }
  }

  /// 未登录 / 退出登录：四域统一回到「未登录」提示，页面保留入口卡片。
  void _setUnauthenticated() {
    _health = const OverviewState<HealthOverview>(
      status: LoadStatus.unauthenticated,
    );
    _finance = const OverviewState<FinanceOverview>(
      status: LoadStatus.unauthenticated,
    );
    _lifestyle = const OverviewState<LifestyleOverview>(
      status: LoadStatus.unauthenticated,
    );
    _investment = const OverviewState<InvestmentOverview>(
      status: LoadStatus.unauthenticated,
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
    super.dispose();
  }
}

