import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 移动端请求的客户端身份标识。
///
/// Flutter 默认 User-Agent 为 `Dart/x.x (dart:io)`，后端活动日志与登录审计
/// 只能看到 `dart`，无法区分真实机型。这里统一改成可读且可解析的格式：
/// `LifeOS/<App 版本> (<厂商> <机型>; Android <系统版本>)`。
///
/// 任一字段读取失败时按 `Android Device` 降级，保证请求始终能正常发出。
abstract final class ClientIdentity {
  static Future<String>? _userAgent;

  /// 获取移动端 User-Agent。
  ///
  /// 首次调用读取设备信息并缓存，后续请求直接复用同一字符串，避免每次请求
  /// 都触发平台通道调用。
  ///
  /// Returns:
  ///     形如 `LifeOS/1.0.0 (Xiaomi 23127PN0CC; Android 14)` 的 ASCII 字符串。
  static Future<String> userAgent() => _userAgent ??= _build();

  /// 读取应用版本与 Android 设备信息并拼接 User-Agent。
  ///
  /// 各读取步骤独立兜底，任何一步失败只影响对应片段，不抛出异常。
  ///
  /// Returns:
  ///     拼接完成的 User-Agent 字符串。
  static Future<String> _build() async {
    final String appVersion = await _appVersion();
    final AndroidDeviceInfo? android = await _androidInfo();
    final String device = _deviceName(android);
    final String os = _osName(android);
    final String app = appVersion.isEmpty ? 'LifeOS' : 'LifeOS/$appVersion';
    return '$app ($device; $os)';
  }

  /// 读取安装包版本号（构建时写入的 `pubspec.yaml` 版本）。
  ///
  /// Returns:
  ///     语义版本号（如 `1.0.0`）；读取失败返回空串，由调用方降级为 `LifeOS`。
  static Future<String> _appVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return info.version.trim();
    } catch (error) {
      debugPrint('[client] 读取应用版本失败：$error');
      return '';
    }
  }

  /// 读取 Android 设备信息（仅 Android 平台）。
  ///
  /// Returns:
  ///     设备信息对象；非 Android 平台或读取失败时返回 null。
  static Future<AndroidDeviceInfo?> _androidInfo() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      return await DeviceInfoPlugin().androidInfo;
    } catch (error) {
      debugPrint('[client] 读取 Android 设备信息失败：$error');
      return null;
    }
  }

  /// 生成设备名称：厂商 + 机型（如 `Xiaomi 23127PN0CC`）。
  ///
  /// Args:
  ///     android: Android 设备信息，可能为 null。
  ///
  /// Returns:
  ///     可读设备名；取不到机型时返回 `Android Device`。
  static String _deviceName(AndroidDeviceInfo? android) {
    if (android == null) {
      return 'Android Device';
    }
    final String manufacturer = _sanitize(android.manufacturer);
    final String model = _sanitize(android.model);
    if (model.isEmpty) {
      return 'Android Device';
    }
    if (manufacturer.isEmpty || manufacturer.toLowerCase() == 'unknown') {
      return model;
    }
    return '$manufacturer $model';
  }

  /// 生成系统版本描述。
  ///
  /// Args:
  ///     android: Android 设备信息，可能为 null。
  ///
  /// Returns:
  ///     形如 `Android 14`；版本号缺失时返回 `Android`。
  static String _osName(AndroidDeviceInfo? android) {
    final String release = android == null
        ? ''
        : _sanitize(android.version.release);
    return release.isEmpty ? 'Android' : 'Android $release';
  }

  /// 清理设备字段：去掉可能破坏 UA 结构的括号与分号，并合并多余空白。
  ///
  /// Args:
  ///     value: 设备信息原始值（厂商 / 机型 / 系统版本）。
  ///
  /// Returns:
  ///     仅含常规字符的紧凑字符串；空值返回空串。
  static String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[();]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
