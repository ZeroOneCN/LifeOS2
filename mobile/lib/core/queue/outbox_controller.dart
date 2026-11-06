import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/preferences_service.dart';
import 'outbox_entry.dart';

/// 离线队列控制器：本地落盘（SharedPreferences）+ 连通性监听 + FIFO 同步。
///
/// 设计要点：
/// - **先落盘再提示**：`enqueueExpense` 写入磁盘后才返回，UI 立刻拿到结果，
///   不需要等 HTTP；断网时不会出现 15 秒转圈。
/// - **连通性驱动**：`Connectivity().onConnectivityChanged` 从断网变联网时
///   自动 `sync()`；登录状态恢复时也会触发。
/// - **FIFO + 失败即停**：按入队顺序推送，第一条失败就保留整条队列并停下，
///   避免后一条先成功导致账目顺序错乱；错误可见、可手动重试。
/// - **去重只是补偿**：同一条目重试前按「日期 + 商品名 + 金额 + 备注」先查重，
///   只在已失败（`retryCount > 0`）时执行，降低误判同额同名的正常消费；
///   不是后端幂等，极端情况仍可能重复（见文档）。
class OutboxController extends ChangeNotifier {
  OutboxController(this._preferences, this._apiClient, this._auth);

  static const String _queueKey = 'outbox.queue.v1';
  static const String _lastSyncKey = 'outbox.last_sync_at';
  static const int _dedupPageSize = 200;

  final PreferencesService _preferences;
  final ApiClient _apiClient;
  final AuthService _auth;
  final List<OutboxEntry> _entries = <OutboxEntry>[];

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  late final VoidCallback _authListener = _onAuthChanged;
  bool _online = true;
  bool _syncing = false;
  String? _lastError;
  DateTime? _lastSyncAt;
  int _localSeq = 0;

  /// 当前队列（按入队顺序，最早的在最前）。
  List<OutboxEntry> get entries => List<OutboxEntry>.unmodifiable(_entries);

  /// 待同步条数。
  int get pendingCount => _entries.length;

  /// 系统连通性（Wi-Fi / 移动网络 / 以太网任一可用即为 true）。
  bool get isOnline => _online;

  /// 是否正在推送。
  bool get isSyncing => _syncing;

  /// 最近一次推送失败原因；成功后清空。
  String? get lastError => _lastError;

  /// 上次成功推送时间。
  DateTime? get lastSyncAt => _lastSyncAt;

  /// 冷启动初始化：加载磁盘队列、读取上次同步时间、订阅连通性与登录状态。
  ///
  /// 必须在 `runApp` 之前 await，保证首屏就能显示待同步条数。
  Future<void> init() async {
    final String? raw = _preferences.readString(_queueKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          _entries
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map((Map item) =>
                      OutboxEntry.fromJson(item.cast<String, dynamic>()))
                  .where((OutboxEntry item) => item.localId.isNotEmpty),
            );
        }
      } on FormatException {
        // 本地数据损坏时丢弃队列，避免启动失败。
        _entries.clear();
      }
    }
    _lastSyncAt = DateTime.tryParse(_preferences.readString(_lastSyncKey) ?? '');
    _online = _hasNetwork(await Connectivity().checkConnectivity());
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    _auth.addListener(_authListener);
    notifyListeners();
    if (_online) {
      unawaited(sync());
    }
  }

  /// 入队一笔支出并立即返回（写入磁盘后才结束 Future）。
  ///
  /// 联网时顺带触发后台同步，但**不等待**推送结果，UI 不转圈。
  Future<OutboxEntry> enqueueExpense(Map<String, dynamic> payload) async {
    _localSeq += 1;
    final OutboxEntry entry = OutboxEntry(
      localId: '${DateTime.now().millisecondsSinceEpoch}-$_localSeq',
      opType: outboxOpCreateExpense,
      payload: payload,
      createdAt: DateTime.now().toIso8601String(),
    );
    _entries.add(entry);
    await _persist();
    notifyListeners();
    if (_online) {
      unawaited(sync());
    }
    return entry;
  }

  /// FIFO 推送：逐条成功出队；第一条失败即停并记录错误。
  ///
  /// 登录态判断用 [AuthService.hasLocalSession] 而不是 [AuthService.isLoggedIn]：
  /// 冷启动断网时 `user` 尚未恢复，但本地令牌仍在，凭它就能推送；
  /// 令牌真失效（401）时请求会失败并保留队列，不会丢数据。
  Future<void> sync() async {
    if (_syncing || !_online || !_auth.hasLocalSession || _entries.isEmpty) {
      return;
    }
    _syncing = true;
    _lastError = null;
    notifyListeners();
    bool pushedAny = false;
    try {
      while (_entries.isNotEmpty) {
        final OutboxEntry entry = _entries.first;
        try {
          await _push(entry);
          pushedAny = true;
          _entries.removeAt(0);
          await _persist();
          notifyListeners();
        } on ApiException catch (error) {
          _entries[0] =
              entry.copyWith(retryCount: entry.retryCount + 1, lastError: error.message);
          await _persist();
          _lastError = error.message;
          notifyListeners();
          break;
        }
      }
      if (pushedAny) {
        _lastSyncAt = DateTime.now();
        await _preferences.writeString(_lastSyncKey, _lastSyncAt!.toIso8601String());
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// 手动重试：先补一次登录态恢复（冷启动断网时 `/auth/me` 未成功），
  /// 再按 FIFO 推送。失败条目留在队首，重试顺序仍是 FIFO。
  Future<void> retryNow() => _recoverThenSync();

  /// 恢复登录态后同步。
  ///
  /// 冷启动断网时 `AuthService.user` 为空（`connectionFailed == true`），
  /// 此时只靠连通性事件不会恢复登录态，导致队列一直不推送；这里先
  /// `restore()`（幂等）再 `sync()`，让「联网即自动推送」在冷启动场景也成立。
  Future<void> _recoverThenSync() async {
    if (_auth.connectionFailed) {
      await _auth.restore();
    }
    await sync();
  }

  /// 推送单条：已知创建支出走「失败后先查重、再 POST」。
  Future<void> _push(OutboxEntry entry) async {
    if (entry.opType != outboxOpCreateExpense) {
      throw ApiException(
        kind: ApiErrorKind.badResponse,
        message: '未知操作类型：${entry.opType}',
      );
    }
    if (entry.retryCount > 0 && await _alreadyCreated(entry)) {
      return;
    }
    await _apiClient.post<Map<String, dynamic>>(
      '/finance/shopping/records',
      data: entry.payload,
    );
  }

  /// 补偿式查重：同日同商品名同金额同备注视为「上次其实已写入」。
  ///
  /// 只在重试（`retryCount > 0`）时调用；查询失败会抛出 ApiException，
  /// 由上层按失败处理（保留队列），不会误删条目。
  Future<bool> _alreadyCreated(OutboxEntry entry) async {
    final String date = entry.payload['record_date'] as String? ?? '';
    if (date.isEmpty) {
      return false;
    }
    final Map<String, dynamic>? json = (await _apiClient.get<Map<String, dynamic>>(
      '/finance/shopping/records',
      queryParameters: <String, dynamic>{
        'start': date,
        'end': date,
        'page': 1,
        'page_size': _dedupPageSize,
      },
    ))
        .data;
    if (json == null) {
      return false;
    }
    final String name = entry.payload['product_name'] as String? ?? '';
    final double amount =
        (entry.payload['total_price'] as num?)?.toDouble() ?? -1;
    final String note = entry.payload['note'] as String? ?? '';
    final List<dynamic> items = json['items'] as List<dynamic>? ?? <dynamic>[];
    return items.whereType<Map>().any((Map item) {
      return (item['product_name'] as String? ?? '') == name &&
          (item['total_price'] as num?)?.toDouble() == amount &&
          (item['note'] as String? ?? '') == note;
    });
  }

  /// 连通性变化：任何非 `none` 结果都视为可用；从断网恢复时自动同步。
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final bool online = _hasNetwork(results);
    final bool recovered = online && !_online;
    _online = online;
    notifyListeners();
    if (recovered) {
      unawaited(_recoverThenSync());
    }
  }

  /// 登录态变化：登录成功后立即补推此前积压的条目。
  void _onAuthChanged() {
    if (_auth.isLoggedIn && _online) {
      unawaited(sync());
    }
  }

  /// 任意非 `none` 结果都代表有可用网络。
  static bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((ConnectivityResult item) => item != ConnectivityResult.none);
  }

  /// 队列整体写回磁盘（整表 JSON 覆盖写，条目量小且需要状态可变）。
  Future<void> _persist() async {
    await _preferences.writeString(
      _queueKey,
      jsonEncode(_entries.map((OutboxEntry entry) => entry.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _auth.removeListener(_authListener);
    super.dispose();
  }
}
