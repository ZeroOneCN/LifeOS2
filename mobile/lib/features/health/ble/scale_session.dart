import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'body_composition.dart';
import 'scale_protocol.dart';

/// 蓝牙权限申请结果。
enum ScalePermissionOutcome {
  /// 已授权。
  granted,

  /// 本次拒绝，可再次申请。
  denied,

  /// 永久拒绝，只能去系统设置里打开。
  permanentlyDenied,

  /// 非 Android 或平台通道不可用。
  unknown,
}

/// Android 运行时蓝牙权限桥。
///
/// Android 12+ 申请 `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`；
/// 12 以下走 `ACCESS_FINE_LOCATION` 兼容分支（逻辑在 MainActivity）。
class ScalePermissionService {
  const ScalePermissionService();

  static const MethodChannel _channel = MethodChannel('com.lifeos.mobile/ble');

  /// 申请扫描与连接所需权限，返回申请结果。
  Future<ScalePermissionOutcome> request() async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'requestBlePermissions',
      );
      switch (result) {
        case 'granted':
          return ScalePermissionOutcome.granted;
        case 'denied':
          return ScalePermissionOutcome.denied;
        case 'permanently_denied':
          return ScalePermissionOutcome.permanentlyDenied;
        default:
          return ScalePermissionOutcome.unknown;
      }
    } on MissingPluginException {
      return ScalePermissionOutcome.unknown;
    } on PlatformException {
      return ScalePermissionOutcome.unknown;
    }
  }

  /// 打开本应用的系统设置页（权限被永久拒绝时使用）。
  Future<bool> openAppSettings() async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>('openAppSettings');
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// 扫描结果条目（只保留界面需要的字段）。
class ScaleDeviceOption {
  const ScaleDeviceOption({
    required this.device,
    required this.name,
    required this.rssi,
    required this.remoteId,
  });

  final BluetoothDevice device;
  final String name;
  final int rssi;
  final String remoteId;
}

/// 一次完整的称重结果。
class ScaleReading {
  const ScaleReading({
    required this.weightKg,
    required this.measuredAt,
    this.impedanceOhm,
    this.bodyComposition,
  });

  final double weightKg;
  final DateTime measuredAt;
  final double? impedanceOhm;
  final BodyCompositionResult? bodyComposition;
}

/// 蓝牙体重秤连接与采集流程。
///
/// 页面状态机：`idle → scanning → connecting → waiting → measured → syncing → synced`
/// 任一阶段失败落到 `error`，界面提供「重试」与「改用手动录入」。
class ScaleSession extends ChangeNotifier {
  ScaleSession({
    required this.apiClient,
    this.permissions = const ScalePermissionService(),
  });

  final ApiClient apiClient;
  final ScalePermissionService permissions;

  ScaleStage _stage = ScaleStage.idle;
  ScaleStage get stage => _stage;

  final List<ScaleDeviceOption> _devices = <ScaleDeviceOption>[];
  List<ScaleDeviceOption> get devices =>
      List<ScaleDeviceOption>.unmodifiable(_devices);

  ScaleReading? _reading;
  ScaleReading? get reading => _reading;

  String? _error;
  String? get error => _error;

  String? _hint;
  String? get hint => _hint;

  bool _permissionBlocked = false;
  bool get permissionBlocked => _permissionBlocked;

  bool _connected = false;
  bool get connected => _connected;

  bool _bluetoothOff = false;

  /// 手机蓝牙适配器是否处于关闭状态。
  bool get bluetoothOff => _bluetoothOff;

  bool _needsPairing = false;

  /// 服务发现失败且设备未配对时为 true，界面引导配对。
  bool get needsPairing => _needsPairing;

  final List<String> _gattLog = <String>[];
  final List<String> _frameLog = <String>[];

  /// GATT 服务枚举记录（调试用，原样展示给用户排查）。
  List<String> get gattLog => List<String>.unmodifiable(_gattLog);

  /// 最近收到的原始通知帧（十六进制，调试用）。
  List<String> get frameLog => List<String>.unmodifiable(_frameLog);

  ScaleDeviceOption? _lastOption;

  DateTime? _syncedAt;
  DateTime? get syncedAt => _syncedAt;

  double _heightCm = 173;
  int _age = 25;
  bool _isMale = true;

  /// 资料用于下发阻抗测量包与体成分估算；默认值与网页端一致，身高默认 173 cm。
  double get heightCm => _heightCm;
  int get age => _age;
  bool get isMale => _isMale;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _scanTimer;
  Timer? _profileTimer;
  Timer? _idleTimer;
  Timer? _stableTimer;
  ScaleMeasurement? _pending;
  int _deviceType = scaleDefaultDeviceType;
  bool _received = false;
  bool _disposed = false;

  /// 更新用户资料（仅未连接时生效，避免中途改变阻抗算法口径）。
  void setProfile({
    required double heightCm,
    required int age,
    required bool isMale,
  }) {
    if (_connected) {
      return;
    }
    _heightCm = heightCm;
    _age = age;
    _isMale = isMale;
    _notify();
  }

  /// 扫描：先申请权限，再过滤广播中带 `0xFFB0` 或名称含 `AFU` / `UAF028` 的设备。
  Future<void> startScan() async {
    if (_stage == ScaleStage.scanning) {
      return;
    }
    await _teardownConnection();
    _devices.clear();
    _error = null;
    _hint = null;
    _permissionBlocked = false;
    _bluetoothOff = false;
    _reading = null;
    _syncedAt = null;
    _needsPairing = false;
    _gattLog.clear();
    _frameLog.clear();

    final bool supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _stage = ScaleStage.error;
      _error = '当前设备不支持低功耗蓝牙（BLE），无法连接体重秤。';
      _notify();
      return;
    }

    final ScalePermissionOutcome outcome = await permissions.request();
    if (outcome == ScalePermissionOutcome.permanentlyDenied) {
      _stage = ScaleStage.error;
      _permissionBlocked = true;
      _error = '蓝牙权限已被永久拒绝，请在系统设置中允许「附近的设备」权限后重试。';
      _notify();
      return;
    }
    if (outcome == ScalePermissionOutcome.denied) {
      _stage = ScaleStage.error;
      _permissionBlocked = true;
      _error = '未获得蓝牙权限，无法扫描体重秤。可重新授权或去设置中开启。';
      _notify();
      return;
    }

    // 适配器关闭时直接给出可操作提示，避免底层抛出原始 PlatformException。
    try {
      final BluetoothAdapterState adapter = await FlutterBluePlus.adapterState
          .firstWhere(
            (BluetoothAdapterState state) =>
                state != BluetoothAdapterState.unknown,
          )
          .timeout(const Duration(seconds: 3));
      if (adapter != BluetoothAdapterState.on) {
        _stage = ScaleStage.error;
        _bluetoothOff = true;
        _error = '手机蓝牙未开启，请打开蓝牙后重新扫描。';
        _notify();
        return;
      }
    } catch (_) {
      // 个别机型拿不到适配器状态时继续尝试扫描，由底层错误兜底。
    }

    _stage = ScaleStage.scanning;
    _notify();

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (Object error) {
        _stage = ScaleStage.error;
        _error = '扫描失败：${_describeError(error)}';
        _notify();
      },
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (error) {
      _stage = ScaleStage.error;
      _error = '无法开始扫描：${_describeError(error)}';
      final String raw = error.toString().toLowerCase();
      if (raw.contains('bluetooth is off') ||
          raw.contains('bluetooth must be turned on') ||
          raw.contains('turned off')) {
        _bluetoothOff = true;
        _error = '手机蓝牙未开启，请打开蓝牙后重新扫描。';
      } else if (raw.contains('permission')) {
        _permissionBlocked = true;
        _error = '缺少蓝牙权限，请允许「附近的设备」权限后重试。';
      }
      _notify();
      return;
    }

    // FBP 的 timeout 只负责停止扫描，这里补一个收尾提示。
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 16), () {
      if (_stage != ScaleStage.scanning) {
        return;
      }
      _stage = ScaleStage.idle;
      if (_devices.isEmpty) {
        _hint = '没有发现体重秤。请踩一下秤面唤醒它，确认秤已进入可连接状态后重新扫描。';
      }
      _notify();
    });
  }

  /// 弹出系统面板开启蓝牙（Android）；取消或失败时返回 false。
  Future<bool> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 停止扫描。
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // 停止扫描失败不影响后续连接。
    }
    if (_stage == ScaleStage.scanning) {
      _stage = ScaleStage.idle;
      _notify();
    }
  }

  /// 连接指定设备：发现 `0xFFB0` 服务 → 订阅 `FFB2` → 下发资料包。
  Future<void> connect(ScaleDeviceOption option) async {
    await stopScan();
    _lastOption = option;
    _needsPairing = false;
    _gattLog.clear();
    _stage = ScaleStage.connecting;
    _error = null;
    _hint = null;
    _notify();
    _device = option.device;

    try {
      await option.device.connect(
        timeout: const Duration(seconds: 20),
        mtu: null,
      );
      _connected = true;
      _connectionSubscription = option.device.connectionState.listen((
        BluetoothConnectionState state,
      ) {
        if (state == BluetoothConnectionState.disconnected && _connected) {
          _connected = false;
          _teardownTimers();
          _stage = ScaleStage.error;
          _error = '蓝牙设备已断开，请重新连接或改用手动录入。';
          _notify();
        }
      });

      final List<BluetoothService> services =
          await _discoverServicesWithRetry(option.device);
      if (!services.any(
        (BluetoothService item) => _uuidEquals(item.uuid, scaleServiceUuid),
      )) {
        // 私有服务缺失：先看配对状态，未配对时给出可操作的配对入口。
        BluetoothBondState bond = BluetoothBondState.none;
        try {
          bond = await option.device.bondState
              .first
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // 拿不到配对状态时按未配对处理。
        }
        _appendGatt('bondState=$bond');
        if (bond != BluetoothBondState.none) {
          throw StateError('设备未提供 0xFFB0 私有服务（已重试 3 次，bond=$bond）');
        }
        _needsPairing = true;
        _stage = ScaleStage.error;
        _error = '未发现 0xFFB0 私有服务（已重试 3 次）。'
            '该秤可能需要先在系统蓝牙中配对后才暴露私有服务，可点击「配对该秤」重试；'
            '完整服务列表见页面底部调试信息。';
        _notify();
        return;
      }
      final BluetoothService service = services.firstWhere(
        (BluetoothService item) => _uuidEquals(item.uuid, scaleServiceUuid),
        orElse: () => throw StateError('设备未提供 0xFFB0 私有服务'),
      );
      final BluetoothCharacteristic writeCharacteristic = service
          .characteristics
          .firstWhere(
            (BluetoothCharacteristic item) =>
                _uuidEquals(item.uuid, scaleWriteUuid),
            orElse: () => throw StateError('设备缺少 0xFFB1 写入特征'),
          );
      _notifyCharacteristic = service.characteristics.firstWhere(
        (BluetoothCharacteristic item) =>
            _uuidEquals(item.uuid, scaleNotifyUuid),
        orElse: () => throw StateError('设备缺少 0xFFB2 通知特征'),
      );

      _valueSubscription = _notifyCharacteristic!.onValueReceived.listen(
        _onFrame,
      );
      await _notifyCharacteristic!.setNotifyValue(true);

      _stage = ScaleStage.waiting;
      _received = false;
      _hint = '已连接。请光脚站上秤并保持双脚覆盖电极 5~8 秒。';
      _notify();

      // 与网页端一致：立即下发资料包，之后每 15 秒重发，确保秤唤醒后不丢失资料。
      await _sendProfile(writeCharacteristic);
      _profileTimer?.cancel();
      _profileTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await _sendProfile(writeCharacteristic);
      });

      // 30 秒没有数据时给温和提示（不主动断开，允许用户随时取消）。
      _idleTimer?.cancel();
      _idleTimer = Timer(const Duration(seconds: 30), () {
        if (_received || !_connected) {
          return;
        }
        _hint =
            '还没有收到称重数据。请确认秤已唤醒、双脚覆盖电极；'
            '若刚连上时秤处于休眠，上秤后才会开始推送。';
        _notify();
      });
    } catch (error) {
      _teardownConnection();
      _stage = ScaleStage.error;
      _error = '连接失败：${_describeError(error)}';
      _notify();
    }
  }

  /// 发现服务并重试：部分秤连接后 1~2 秒才完成 GATT 注册，过早枚举会得到空列表。
  ///
  /// 每次枚举的完整 service / characteristic UUID 都写入调试日志，便于真机取证。
  Future<List<BluetoothService>> _discoverServicesWithRetry(
    BluetoothDevice device,
  ) async {
    List<BluetoothService> services = <BluetoothService>[];
    for (int attempt = 1; attempt <= 3; attempt++) {
      services = await device.discoverServices();
      _appendGatt('第 $attempt 次 discoverServices：${services.length} 个服务');
      for (final BluetoothService service in services) {
        _appendGatt(
          '  service ${service.uuid.str128} (short=${service.uuid.str})',
        );
        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          _appendGatt(
            '    char ${characteristic.uuid.str128} '
            'props=${characteristic.properties}',
          );
        }
      }
      if (services.any(
        (BluetoothService item) => _uuidEquals(item.uuid, scaleServiceUuid),
      )) {
        return services;
      }
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    return services;
  }

  /// 追加一条 GATT 调试记录，同时输出到 logcat（`adb logcat -s flutter`）。
  void _appendGatt(String line) {
    _gattLog.add(line);
    debugPrint('LIFEOS_BLE $line');
  }

  /// 引导系统配对后重新连接（仅在私有服务缺失且未配对时使用）。
  Future<void> pairAndReconnect() async {
    final ScaleDeviceOption? option = _lastOption;
    final BluetoothDevice? device = _device;
    if (option == null || device == null) {
      return;
    }
    _stage = ScaleStage.connecting;
    _error = null;
    _hint = '正在系统配对，请在弹窗中确认…';
    _notify();
    try {
      await device.createBond(timeout: 60);
      _appendGatt('createBond 成功');
    } catch (error) {
      _appendGatt('createBond 失败：${_describeError(error)}');
      _stage = ScaleStage.error;
      _needsPairing = true;
      _error = '配对失败：${_describeError(error)}';
      _notify();
      return;
    }
    await _teardownConnection();
    await connect(option);
  }

  /// 下发「时间 + 用户资料」包（0xD0），使能阻抗测量。
  Future<void> _sendProfile(BluetoothCharacteristic writeCharacteristic) async {
    if (!_connected) {
      return;
    }
    try {
      await writeCharacteristic.write(
        buildScaleUserInfoPacket(
          deviceType: _deviceType,
          heightCm: _heightCm.round(),
          age: _age,
          isMale: _isMale,
        ),
        withoutResponse: true,
      );
    } catch (_) {
      // 下发失败不致命：秤仍可只称体重。
    }
  }

  /// 收到 FFB2 通知：解析 → 只接受稳定且合理的读数 → 等 3 秒合并阻抗包。
  void _onFrame(List<int> value) {
    final String hex = value
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _frameLog.add('RX $hex');
    if (_frameLog.length > 30) {
      _frameLog.removeAt(0);
    }
    debugPrint('LIFEOS_BLE RX $hex');
    if (value.length >= 2) {
      _deviceType = value[1];
    }
    final ScaleMeasurement? parsed = parseScaleFrame(Uint8List.fromList(value));
    if (parsed == null || parsed.isAck) {
      return;
    }
    if (!parsed.weight.stable || !isValidScaleGrams(parsed.weight.grams)) {
      return;
    }
    _received = true;
    _pending = parsed;
    _stableTimer?.cancel();
    _stableTimer = Timer(const Duration(seconds: 3), _finalizeReading);
  }

  /// 合并等待期间的最后一条数据，产出体重 + 可选的阻抗 / 体成分。
  void _finalizeReading() {
    final ScaleMeasurement? finalFrame = _pending;
    _pending = null;
    if (finalFrame == null) {
      return;
    }
    final double weightKg = (finalFrame.weight.kg * 100).round() / 100;

    double? impedanceOhm;
    BodyCompositionResult? composition;
    final List<int>? channels = finalFrame.impedances;
    // 0 值表示本次未形成有效测量回路（如未光脚），按「未采集」处理。
    if (finalFrame.isImpedance && channels != null && channels[0] > 0) {
      impedanceOhm = (channels[0] * 10).round() / 10;
      composition = calculateBodyComposition(
        weightKg: weightKg,
        impedanceOhm: impedanceOhm,
        heightCm: _heightCm,
        age: _age,
        isMale: _isMale,
      );
    }

    _reading = ScaleReading(
      weightKg: weightKg,
      impedanceOhm: impedanceOhm,
      bodyComposition: composition,
      measuredAt: DateTime.now(),
    );
    _stage = ScaleStage.measured;
    _hint = null;
    _error = null;
    _idleTimer?.cancel();
    _notify();
  }

  /// 把当前读数写入 `POST /health/body/blesync`。
  ///
  /// 后端契约是「按服务器今天覆盖、只写入传入字段」，无需整条记录合并；
  /// 但仍显式省略 null / 0 字段，避免用 0 覆盖历史体成分。
  Future<bool> syncToServer() async {
    final ScaleReading? current = _reading;
    if (current == null) {
      _error = '还没有测量数据';
      _notify();
      return false;
    }
    _stage = ScaleStage.syncing;
    _error = null;
    _notify();

    final Map<String, dynamic> payload = <String, dynamic>{
      'weight_kg': current.weightKg,
      'height_cm': _heightCm,
      'gender': _isMale ? 'male' : 'female',
      'measured_at': current.measuredAt.toUtc().toIso8601String(),
    };
    final double? impedance = current.impedanceOhm;
    if (impedance != null && impedance > 0) {
      payload['impedance_ohm'] = impedance;
    }
    final BodyCompositionResult? composition = current.bodyComposition;
    if (composition != null) {
      payload['body_composition'] = composition.toJson();
    }

    try {
      await apiClient.post<Map<String, dynamic>>(
        '/health/body/blesync',
        data: payload,
      );
      _stage = ScaleStage.synced;
      _syncedAt = DateTime.now();
      _notify();
      return true;
    } on ApiException catch (error) {
      _stage = ScaleStage.measured;
      _error = '同步失败：${error.message}';
      _notify();
      return false;
    }
  }

  /// 断开连接并回到初始态（保留最后一次读数，便于再次同步）。
  Future<void> disconnect() async {
    await _teardownConnection();
    _stage = ScaleStage.idle;
    _hint = null;
    _notify();
  }

  /// 扫描结果去重、过滤与排序（信号强的在前）。
  void _onScanResults(List<ScanResult> results) {
    final Map<String, ScaleDeviceOption> matched =
        <String, ScaleDeviceOption>{};
    for (final ScanResult result in results) {
      if (!_isScaleAdvertisement(result)) {
        continue;
      }
      final String name = _displayName(result);
      matched[result.device.remoteId.str] = ScaleDeviceOption(
        device: result.device,
        name: name.isEmpty ? '体重秤（未命名）' : name,
        rssi: result.rssi,
        remoteId: result.device.remoteId.str,
      );
    }
    _devices
      ..clear()
      ..addAll(matched.values);
    _devices.sort(
      (ScaleDeviceOption a, ScaleDeviceOption b) => b.rssi.compareTo(a.rssi),
    );
    if (_devices.isNotEmpty) {
      _hint = '发现 ${_devices.length} 台设备，点选后连接。';
    }
    _notify();
  }

  /// 比较特征 UUID。
  ///
  /// `Guid.str` 会把标准 128 位 UUID 缩成 16 位（`ffb0`），必须用 `str128` 比较。
  bool _uuidEquals(Guid uuid, String expected) =>
      uuid.str128.toLowerCase() == expected;

  /// 服务 UUID 优先识别；名称仅兜底（实测广播名 `UAF028`，既不以 AFU 开头也不含 AFU）。
  bool _isScaleAdvertisement(ScanResult result) {
    final bool hasService = result.advertisementData.serviceUuids.any(
      (Guid uuid) => uuid.str128.toLowerCase().contains('0000ffb0'),
    );
    if (hasService) {
      return true;
    }
    final String name = _displayName(result).toUpperCase();
    return name.startsWith('AFU') || name.contains('UAF028');
  }

  /// 优先广播名，其次系统缓存名。
  String _displayName(ScanResult result) {
    final String advName = result.advertisementData.advName.trim();
    if (advName.isNotEmpty) {
      return advName;
    }
    return result.device.platformName.trim();
  }

  /// 把底层异常转成可读提示。
  String _describeError(Object error) {
    if (error is FlutterBluePlusException) {
      final String? description = error.description;
      if (description != null && description.isNotEmpty) {
        return description;
      }
      return '蓝牙操作失败（错误码 ${error.code}）';
    }
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }

  /// 取消所有定时器与订阅。
  void _teardownTimers() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _profileTimer?.cancel();
    _profileTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _pending = null;
  }

  /// 断开 GATT 并清理连接相关资源（不影响已同步结果）。
  Future<void> _teardownConnection() async {
    _teardownTimers();
    try {
      await _valueSubscription?.cancel();
    } catch (_) {
      // 忽略取消订阅异常。
    }
    _valueSubscription = null;
    try {
      await _connectionSubscription?.cancel();
    } catch (_) {
      // 忽略取消监听异常。
    }
    _connectionSubscription = null;
    _notifyCharacteristic = null;
    final BluetoothDevice? device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {
        // 已断开时再次 disconnect 可能报错，忽略。
      }
    }
    _connected = false;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}

/// 页面状态机。
enum ScaleStage {
  /// 未开始。
  idle,

  /// 扫描中。
  scanning,

  /// 连接中。
  connecting,

  /// 已连接，等待上秤。
  waiting,

  /// 已读取到稳定称重结果。
  measured,

  /// 正在写入后端。
  syncing,

  /// 写入成功。
  synced,

  /// 失败（权限 / 连接 / 同步）。
  error,
}
