import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/preferences_service.dart';
import 'outbox_entry.dart';

/// 离线队列：本地落盘 + 连通性监听 + FIFO 同步。
///
/// 设计要点：
/// - **持久化**：整表 JSON 写入 `SharedPreferences`（`outbox.queue.v1`），
///   冷启动在 `runApp` 前加载，队列不会因杀进程丢失。
/// - **断网立即返回**：入队只写本地，不发 HTTP；页面立刻能显示「待同步」。
/// - **FIFO**：按入队顺序逐条推送，第一条失败即停，避免后面的写操作越过失败的写操作。
/// - **自动退避**：失败后按 1s / 5s / 30s / 2min 重试，超过 4 次停为「需手动重试」，
///   不在后台快速轮询耗电。
/// - **上限**：最多 [maxEntries] 条，超限拒绝新写入并提示先同步。
/// - **幂等**：后端没有幂等键。创建类操作在重试前做查重补偿；用药打卡走 PUT，
///   按记录 id 天然幂等，不做查重。
class OutboxController extends ChangeNotifier {
  OutboxController(this._preferences, this._apiClient, this._auth);

  /// 队列上限：超过后拒绝新写入，避免长期离线无限堆积。
  static const int maxEntries = 200;

  /// 失败后的自动重试间隔（第 1~4 次）。第 5 次失败后停在「需手动重试」。
  static const List<Duration> retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];

  static const String _queueKey = 'outbox.queue.v1';
  static const String _syncAtKey = 'outbox.last_sync_at';

  final PreferencesService _preferences;
  final ApiClient _apiClient;
  final AuthService _auth;

  final List<OutboxEntry> _entries = <OutboxEntry>[];
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _online = true;
  bool _syncing = false;
  String? _lastError;
  DateTime? _lastSyncAt;
  Timer? _retryTimer;
  DateTime? _nextRetryAt;
  int _localSeq = 0;

  /// 队列快照（只读）。
  List<OutboxEntry> get entries => List<OutboxEntry>.unmodifiable(_entries);

  int get pendingCount => _entries.length;

  bool get isOnline => _online;

  bool get isSyncing => _syncing;

  /// 最近一次推送失败原因（成功后清空）。
  String? get lastError => _lastError;

  DateTime? get lastSyncAt => _lastSyncAt;

  /// 下一次自动重试的时间；为空表示当前没有等待中的自动重试。
  DateTime? get nextRetryAt => _nextRetryAt;

  /// 自动重试次数已用尽，失败条目只能手动重试。
  bool get needsManualRetry =>
      _entries.isNotEmpty &&
      _entries.first.retryCount > retryDelays.length;

  /// 队列是否已达上限（新写入会被拒绝）。
  bool get isFull => _entries.length >= maxEntries;

  /// 冷启动加载队列、读取上次同步时间并订阅连通性与登录态。
  Future<void> init() async {
    final String? raw = _preferences.readString(_queueKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        _entries.addAll(
          list
              .whereType<Map>()
              .map((Map item) =>
                  OutboxEntry.fromJson(item.cast<String, dynamic>()))
              .toList(),
        );
      } catch (_) {
        // 坏数据不应阻塞启动：清空并覆盖为空数组。
        _entries.clear();
        await _preferences.writeString(_queueKey, '[]');
      }
    }
    final String? syncAt = _preferences.readString(_syncAtKey);
    _lastSyncAt = syncAt == null ? null : DateTime.tryParse(syncAt);

    try {
      _online = _hasNetwork(await _connectivity.checkConnectivity());
    } catch (_) {
      // 平台通道不可用时按在线处理，避免永远不推送。
      _online = true;
    }
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _auth.addListener(_onAuthChanged);
    notifyListeners();

    if (_online) {
      unawaited(sync());
    }
  }

  /// 按操作类型取待同步条目（页面用来区分财务 / 用药 / 外汇）。
  List<OutboxEntry> pendingOf(String opType) {
    return _entries
        .where((OutboxEntry entry) => entry.opType == opType)
        .toList(growable: false);
  }

  /// 指定操作类型是否有针对某条服务端记录（`payload['id']`）的待同步操作。
  bool hasPendingTarget(String opType, int targetId) {
    return _entries.any(
      (OutboxEntry entry) =>
          entry.opType == opType &&
          (entry.payload['id'] as num?)?.toInt() == targetId,
    );
  }

  /// 某条记录待同步的请求体（用于本地乐观展示）。
  Map<String, dynamic>? pendingPayloadFor(String opType, int targetId) {
    for (final OutboxEntry entry in _entries) {
      if (entry.opType == opType &&
          (entry.payload['id'] as num?)?.toInt() == targetId) {
        return entry.payload;
      }
    }
    return null;
  }

  /// 入队一条写操作。
  ///
  /// 返回 `null` 表示队列已达上限，调用方应提示用户先同步。
  Future<OutboxEntry?> enqueue(
    String opType,
    Map<String, dynamic> payload,
  ) async {
    if (_entries.length >= maxEntries) {
      return null;
    }
    final OutboxEntry entry = OutboxEntry(
      localId: '${DateTime.now().microsecondsSinceEpoch}-${_localSeq++}',
      opType: opType,
      payload: payload,
      createdAt: DateTime.now().toIso8601String(),
      retryCount: 0,
      lastError: null,
    );
    _entries.add(entry);
    await _persist();
    notifyListeners();
    if (_online && _auth.hasLocalSession) {
      unawaited(sync());
    }
    return entry;
  }

  /// 财务记一笔支出入队。
  Future<OutboxEntry?> enqueueExpense(Map<String, dynamic> payload) {
    return enqueue(outboxOpCreateExpense, payload);
  }

  /// 用药打卡入队（按记录 id 更新三餐状态）。
  Future<OutboxEntry?> enqueueMedicationCheckin(
    Map<String, dynamic> payload,
  ) {
    return enqueue(outboxOpMedicationCheckin, payload);
  }

  /// 新增外汇交易入队。
  Future<OutboxEntry?> enqueueForexCreate(Map<String, dynamic> payload) {
    return enqueue(outboxOpForexCreate, payload);
  }

  /// 手动重试：立即推送，不受退避计时限制。
  Future<void> retryNow() async {
    _retryTimer?.cancel();
    _nextRetryAt = null;
    notifyListeners();
    await _recoverThenSync();
  }

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
    _retryTimer?.cancel();
    _nextRetryAt = null;
    notifyListeners();

    bool pushedAny = false;
    try {
      while (_entries.isNotEmpty) {
        final OutboxEntry entry = _entries.first;
        try {
          await _push(entry);
        } on ApiException catch (error) {
          final OutboxEntry failed = entry.copyWith(
            retryCount: entry.retryCount + 1,
            lastError: error.message,
          );
          _entries[0] = failed;
          _lastError = error.message;
          await _persist();
          _scheduleAutoRetry(failed.retryCount);
          notifyListeners();
          return;
        }
        _entries.removeAt(0);
        await _persist();
        pushedAny = true;
        notifyListeners();
      }
    } finally {
      if (pushedAny) {
        _lastSyncAt = DateTime.now();
        unawaited(
          _preferences.writeString(_syncAtKey, _lastSyncAt!.toIso8601String()),
        );
      }
      _syncing = false;
      if (_entries.isEmpty) {
        _retryTimer?.cancel();
        _nextRetryAt = null;
      }
      notifyListeners();
    }
  }

  /// 按失败次数安排下一次自动重试；次数用尽后不再自动重试。
  void _scheduleAutoRetry(int retryCount) {
    _retryTimer?.cancel();
    if (retryCount > retryDelays.length) {
      _nextRetryAt = null;
      return;
    }
    final Duration delay = retryDelays[retryCount - 1];
    _nextRetryAt = DateTime.now().add(delay);
    _retryTimer = Timer(delay, () {
      _nextRetryAt = null;
      notifyListeners();
      if (_online) {
        unawaited(_recoverThenSync());
      }
    });
  }

  /// 按操作类型分发到对应接口。
  Future<void> _push(OutboxEntry entry) async {
    switch (entry.opType) {
      case outboxOpCreateExpense:
        if (entry.retryCount > 0 && await _expenseAlreadyCreated(entry)) {
          return;
        }
        await _apiClient.post<Map<String, dynamic>>(
          '/finance/shopping/records',
          data: entry.payload,
        );
        break;
      case outboxOpMedicationCheckin:
        // PUT 全量更新三餐状态：同一 payload 重复执行结果一致，天然幂等。
        final Map<String, dynamic> data =
            Map<String, dynamic>.of(entry.payload);
        final int id = (data.remove('id') as num?)?.toInt() ?? 0;
        if (id <= 0) {
          throw const ApiException(
            kind: ApiErrorKind.badResponse,
            message: '用药打卡缺少记录 id',
          );
        }
        await _apiClient.put<Map<String, dynamic>>(
          '/health/medication/$id',
          data: data,
        );
        break;
      case outboxOpForexCreate:
        if (entry.retryCount > 0 && await _forexAlreadyCreated(entry)) {
          return;
        }
        await _apiClient.post<Map<String, dynamic>>(
          '/investment/forex',
          data: entry.payload,
        );
        break;
      default:
        throw ApiException(
          kind: ApiErrorKind.badResponse,
          message: '未知的队列操作类型：${entry.opType}',
        );
    }
  }

  /// 支出查重（补偿）：同日期 + 商品名 + 金额 + 备注。
  Future<bool> _expenseAlreadyCreated(OutboxEntry entry) async {
    final String date = entry.payload['record_date'] as String? ?? '';
    if (date.isEmpty) {
      return false;
    }
    final Map<String, dynamic>? json = (await _apiClient
            .get<Map<String, dynamic>>(
      '/finance/shopping/records',
      queryParameters: <String, dynamic>{
        'start': date,
        'end': date,
        'page': 1,
        'page_size': 200,
      },
    ))
        .data;
    final List<dynamic> items =
        (json?['items'] as List<dynamic>?) ?? <dynamic>[];
    final String name = entry.payload['product_name'] as String? ?? '';
    final String note = entry.payload['note'] as String? ?? '';
    final Object? price = entry.payload['total_price'];
    return items.whereType<Map>().any((Map item) {
      return (item['product_name'] as String? ?? '') == name &&
          (item['note'] as String? ?? '') == note &&
          _sameNumber(item['total_price'], price);
    });
  }

  /// 外汇交易查重（补偿）：同日期 + 品种 + 方向 + 开平仓价 + 手数 + 盈亏/费用 + 备注。
  ///
  /// 组合比支出更严格，降低「同日同品种两笔正常交易」被误判为重复的概率；
  /// 但仍不是真幂等，见文档的限制说明。
  Future<bool> _forexAlreadyCreated(OutboxEntry entry) async {
    final String date = entry.payload['trade_date'] as String? ?? '';
    if (date.isEmpty) {
      return false;
    }
    final Map<String, dynamic>? json = (await _apiClient
            .get<Map<String, dynamic>>(
      '/investment/forex',
      queryParameters: <String, dynamic>{
        'start': date,
        'end': date,
        'page': 1,
        'page_size': 100,
      },
    ))
        .data;
    final List<dynamic> items =
        (json?['items'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> payload = entry.payload;
    return items.whereType<Map>().any((Map item) {
      return (item['symbol'] as String? ?? '') ==
              (payload['symbol'] as String? ?? '') &&
          (item['order_type'] as String? ?? '') ==
              (payload['order_type'] as String? ?? '') &&
          _sameNumber(item['open_price'], payload['open_price']) &&
          _sameNumber(item['lot_size'], payload['lot_size']) &&
          _sameNumber(item['close_price'], payload['close_price']) &&
          _sameNumber(item['pnl'], payload['pnl']) &&
          _sameNumber(item['commission'], payload['commission']) &&
          _sameNumber(item['overnight_fee'], payload['overnight_fee']) &&
          (item['note'] as String? ?? '').trim() ==
              (payload['note'] as String? ?? '').trim();
    });
  }

  /// 数值比较：两边都为空视为相同，否则按 double 比较。
  bool _sameNumber(Object? a, Object? b) {
    final double? left = (a as num?)?.toDouble();
    final double? right = (b as num?)?.toDouble();
    if (left == null || right == null) {
      return left == right;
    }
    return (left - right).abs() < 1e-9;
  }

  /// 连通性变化：恢复网络时先补登录态再推送，并取消等待中的退避计时。
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final bool online = _hasNetwork(results);
    final bool recovered = online && !_online;
    _online = online;
    if (recovered) {
      _retryTimer?.cancel();
      _nextRetryAt = null;
    }
    notifyListeners();
    if (recovered) {
      unawaited(_recoverThenSync());
    }
  }

  /// 登录态恢复后重试（冷启动在线时由这里接手）。
  void _onAuthChanged() {
    if (_auth.isLoggedIn && _online) {
      unawaited(sync());
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((ConnectivityResult result) =>
        result != ConnectivityResult.none);
  }

  Future<void> _persist() async {
    await _preferences.writeString(
      _queueKey,
      jsonEncode(
        _entries.map((OutboxEntry entry) => entry.toJson()).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
