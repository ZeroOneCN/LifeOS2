import 'package:flutter/services.dart';

/// 拉起系统安装器失败的原因。
enum InstallBridgeError {
  /// 没有授予「安装未知应用」权限。
  permissionDenied,

  /// 设备上没有能处理 APK 的 Activity（个别精简 ROM）。
  installerMissing,

  /// 文件无法通过 FileProvider 暴露（路径不在声明范围内）。
  fileUnavailable,

  /// 其它平台错误。
  unknown,
}

/// 安装桥接失败异常。
class InstallBridgeException implements Exception {
  const InstallBridgeException(this.error, this.message);

  final InstallBridgeError error;
  final String message;

  @override
  String toString() => message;
}

/// 与原生层通信：查询安装权限、跳转授权页、拉起系统安装器。
///
/// 只做很薄的三件事，不用第三方「打开文件」插件：
/// 插件的 FileProvider authority 容易和本项目的 `<applicationId>.fileprovider`
/// 冲突，manifest 合并会直接报错。
class InstallBridge {
  const InstallBridge();

  static const MethodChannel _channel = MethodChannel(
    'com.lifeos.mobile/updater',
  );

  /// 查询当前是否允许本应用安装 APK（Android 8.0+ 按应用授权）。
  ///
  /// Returns:
  ///   已授权返回 true；查询失败按未授权处理，交给界面引导。
  Future<bool> canRequestInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳转「安装未知应用」授权页（指向本应用）。
  ///
  /// Returns:
  ///   跳转是否成功发起。
  Future<bool> openInstallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 用 FileProvider `content://` 地址拉起系统安装器。
  ///
  /// 注意：安装完成后系统会杀掉当前进程，调用方不要依赖返回后的继续执行。
  ///
  /// Args:
  ///   filePath: APK 的绝对路径（必须位于 `external-files-path/updates/` 下）。
  ///
  /// Throws:
  ///   InstallBridgeException: 权限未开、安装器缺失或文件不可用。
  Future<void> installApk(String filePath) async {
    try {
      await _channel.invokeMethod<void>('installApk', <String, dynamic>{
        'path': filePath,
      });
    } on PlatformException catch (error) {
      switch (error.code) {
        case 'permission_denied':
          throw InstallBridgeException(
            InstallBridgeError.permissionDenied,
            error.message ?? '未授予「安装未知应用」权限',
          );
        case 'installer_missing':
          throw InstallBridgeException(
            InstallBridgeError.installerMissing,
            error.message ?? '系统没有可用的安装器',
          );
        case 'file_unavailable':
          throw InstallBridgeException(
            InstallBridgeError.fileUnavailable,
            error.message ?? '安装包路径无法共享给安装器',
          );
        default:
          throw InstallBridgeException(
            InstallBridgeError.unknown,
            error.message ?? '拉起安装器失败（${error.code}）',
          );
      }
    } on MissingPluginException {
      throw const InstallBridgeException(
        InstallBridgeError.installerMissing,
        '当前设备不支持应用内安装',
      );
    }
  }
}
