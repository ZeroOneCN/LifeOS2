import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/api_client.dart';
import '../storage/preferences_service.dart';
import 'release_info.dart';
import 'update_service.dart';

/// 一次检查更新的结果。
enum UpdateCheckResult {
  /// 已是最新版本。
  upToDate,

  /// 有新版本。
  available,

  /// 检查失败（原因见 [UpdateController.lastFailure]）。
  failed,
}

/// 检查更新的状态中心。
///
/// 职责只有两件：
/// 1. 记住「当前安装版本」与「服务器最新版本」，供关于页 / 设置页显示更新标记；
/// 2. 启动时静默检查一次（不弹窗、失败不打扰）。
///
/// 下载与安装由更新页自己做，避免一个 Controller 同时承担长任务与全局状态。
class UpdateController extends ChangeNotifier {
  UpdateController({
    required PreferencesService preferences,
    required ApiClient apiClient,
    UpdateService? service,
  }) : this._(preferences, apiClient, service ?? UpdateService());

  UpdateController._(this._preferences, this._apiClient, this._service);

  final PreferencesService _preferences;
  final ApiClient _apiClient;
  final UpdateService _service;

  String _currentVersionName = '';
  int _currentVersionCode = 0;
  bool _checking = false;
  ReleaseInfo? _latest;
  UpdateFailure? _lastFailure;
  DateTime? _lastCheckedAt;
  bool _latestFromStore = false;

  /// 已安装版本（versionName），未加载完成时为空串。
  String get currentVersionName => _currentVersionName;

  /// 已安装构建号（versionCode），未加载完成时为 0。
  int get currentVersionCode => _currentVersionCode;

  /// 是否正在检查（手动检查时用于禁用按钮）。
  bool get checking => _checking;

  /// 服务器最新版本；从未成功拉取清单时为 null。
  ReleaseInfo? get latest => _latest;

  /// 最近一次失败原因；成功或未检查时为 null。
  UpdateFailure? get lastFailure => _lastFailure;

  /// 最近一次检查时间。
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// 最近一次成功结果是否来自应用仓库（否则来自自建服务器清单）。
  bool get latestFromStore => _latestFromStore;

  /// 更新服务器根地址：设置里填了就用它，否则跟随当前 API 的 host。
  String get serverBase => _preferences.updateBaseUrl ?? _apiClient.origin;

  /// 更新服务器地址是否跟随 API 自动派生。
  bool get serverBaseFollowsApi => _preferences.updateBaseUrl == null;

  /// 下载/校验用的服务实例（更新页直接使用，避免重复创建 Dio）。
  UpdateService get service => _service;

  /// 是否存在可安装的新版本。
  ///
  /// 必须同时满足「语义版本更新」与「构建号大于已装版本」：
  /// 后者是 Android 的硬门槛，构建号不涨的包系统会拒绝安装。
  bool get hasUpdate {
    final ReleaseInfo? latest = _latest;
    if (latest == null || _currentVersionCode <= 0) {
      return false;
    }
    return latest.isNewerThan(
          currentVersionName: _currentVersionName,
          currentVersionCode: _currentVersionCode,
        ) &&
        latest.canInstallOver(_currentVersionCode);
  }

  /// 读取安装包版本信息；`main` 中在 `runApp` 前 await，保证首帧就有版本号。
  Future<void> init() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _currentVersionName = info.version;
      _currentVersionCode = int.tryParse(info.buildNumber) ?? 0;
    } on Object {
      // 读不到版本（极少见）时保持空值，检查更新会提示先确认安装包信息
      _currentVersionName = '';
      _currentVersionCode = 0;
    }
    notifyListeners();
  }

  /// 启动时静默检查：不弹窗、不显示错误，只在发现新版时点亮更新标记。
  ///
  /// 任何失败都只记录在内存里而不打扰用户 —— 局域网服务器可能没开，
  /// 不能因为检查不到更新就挡住正常使用。
  Future<void> checkSilently() async {
    if (_checking || _currentVersionCode <= 0) {
      return;
    }
    await _check(markFailure: false);
  }

  /// 手动检查：返回结果并记录失败原因，供更新页展示。
  ///
  /// Args:
  ///   无。
  ///
  /// Returns:
  ///   [UpdateCheckResult] 三态结果。
  Future<UpdateCheckResult> check() async {
    if (_checking) {
      return hasUpdate
          ? UpdateCheckResult.available
          : UpdateCheckResult.upToDate;
    }
    return _check(markFailure: true);
  }

  /// 检查主体：拉清单 → 解析 → 比较版本。
  ///
  /// Args:
  ///   markFailure: 是否把失败原因暴露给界面（静默检查传 false）。
  ///
  /// Returns:
  ///   三态结果。
  Future<UpdateCheckResult> _check({required bool markFailure}) async {
    _checking = true;
    if (markFailure) {
      _lastFailure = null;
      notifyListeners();
    }
    try {
      try {
        // 优先应用仓库：团队统一发布渠道，返回 null 表示已是最新。
        final ReleaseInfo? store = await _service.fetchFromStore(
          versionCode: _currentVersionCode,
        );
        _latest = store;
        _latestFromStore = true;
        return _finishCheck();
      } on UpdateFailure {
        // 未上架或仓库不可达：回退自建服务器清单（局域网 / 自托管场景）。
        final ReleaseInfo info = await _service.fetchManifest(serverBase);
        _latest = info;
        _latestFromStore = false;
        return _finishCheck();
      }
    } on UpdateFailure catch (failure) {
      _checking = false;
      if (markFailure) {
        _lastFailure = failure;
        notifyListeners();
      }
      return UpdateCheckResult.failed;
    } on Object catch (error) {
      _checking = false;
      if (markFailure) {
        _lastFailure = UpdateFailure(
          UpdateFailureKind.unknown,
          '检查更新失败：$error',
        );
        notifyListeners();
      }
      return UpdateCheckResult.failed;
    }
  }

  /// 收尾一次成功的检查：刷新检查时间、通知界面并给出三态结果。
  ///
  /// Returns:
  ///   [UpdateCheckResult.available] 或 [UpdateCheckResult.upToDate]。
  UpdateCheckResult _finishCheck() {
    _lastCheckedAt = DateTime.now();
    _checking = false;
    notifyListeners();
    return hasUpdate
        ? UpdateCheckResult.available
        : UpdateCheckResult.upToDate;
  }
}
