/// 服务端版本清单的客户端模型与版本比较规则。
///
/// 清单由发布脚本生成（`scripts/build_release_apk.ps1`），字段见
/// `docs/部署与更新/01_检查更新方案.md` §3.2；本版砍掉了强制更新与灰度，
/// 只保留「有没有新版、怎么下载、下完怎么校验」。
library;

/// 清单解析失败：字段缺失、类型不符或 versionName 不符合三段式。
///
/// 与「连不上服务器」严格区分：前者说明服务端清单坏了，后者是网络问题，
/// 界面上要给不同提示。
class ManifestFormatException implements Exception {
  const ManifestFormatException(this.field, this.message);

  /// 出错的字段名；整体格式错误时用 `_file`。
  final String field;

  /// 面向用户的中文说明。
  final String message;

  @override
  String toString() => 'ManifestFormatException($field): $message';
}

/// 解析后的版本清单。
class ReleaseInfo {
  const ReleaseInfo({
    required this.manifestVersion,
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.releaseNotes,
    required this.publishedAt,
    this.minAndroidSdk,
    this.signingCertSha256 = '',
  });

  final int manifestVersion;
  final String versionName;
  final int versionCode;

  /// 可能是绝对地址，也可以是以 `/` 开头的相对路径（由客户端按更新服务器补全）。
  final String downloadUrl;

  /// 小写 64 位十六进制。
  final String sha256;

  /// 安装包字节数。
  final int size;

  final String releaseNotes;
  final String publishedAt;
  final int? minAndroidSdk;
  final String signingCertSha256;

  /// 从接口 JSON 构造清单，逐个字段校验类型与格式。
  ///
  /// Args:
  ///   json: 接口返回的原始 JSON 对象。
  ///
  /// Returns:
  ///   校验通过的 [ReleaseInfo]。
  ///
  /// Throws:
  ///   ManifestFormatException: 必填字段缺失、类型不符或版本号格式非法。
  static ReleaseInfo parse(Map<String, dynamic> json) {
    final int manifestVersion = _asInt(json, 'manifest_version');
    if (manifestVersion < 1) {
      throw const ManifestFormatException('manifest_version', '清单版本号必须 ≥ 1');
    }
    final String platform = _asString(json, 'platform');
    if (platform != 'android') {
      throw ManifestFormatException('platform', '清单平台为 $platform，不是 android');
    }
    final String versionName = _asString(json, 'version_name');
    final List<int>? parts = parseVersionName(versionName);
    if (parts == null) {
      throw ManifestFormatException(
        'version_name',
        '版本号「$versionName」不是三段式（如 1.0.0）',
      );
    }
    final int versionCode = _asInt(json, 'version_code');
    if (versionCode <= 0) {
      throw const ManifestFormatException('version_code', '构建号必须为正整数');
    }
    final String downloadUrl = _asString(json, 'download_url').trim();
    if (downloadUrl.isEmpty) {
      throw const ManifestFormatException('download_url', '下载地址为空');
    }
    final String sha256 = _asString(json, 'sha256').trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const ManifestFormatException('sha256', 'SHA-256 不是 64 位十六进制');
    }
    final int size = _asInt(json, 'size');
    if (size <= 0) {
      throw const ManifestFormatException('size', '安装包大小必须为正整数');
    }
    final Object? sdk = json['min_android_sdk'];
    final Object? cert = json['signing_cert_sha256'];
    return ReleaseInfo(
      manifestVersion: manifestVersion,
      versionName: versionName,
      versionCode: versionCode,
      downloadUrl: downloadUrl,
      sha256: sha256,
      size: size,
      releaseNotes: (json['release_notes'] as String?)?.trim() ?? '',
      publishedAt: (json['published_at'] as String?)?.trim() ?? '',
      minAndroidSdk: sdk is int && !sdk.isNegative ? sdk : null,
      signingCertSha256: cert is String ? cert.trim() : '',
    );
  }

  /// 是否比当前安装版本更新。
  ///
  /// 规则：先按 `major.minor.patch` 比语义版本，相同再比 `versionCode`
  /// （用于同日热修）。禁止字符串比较，否则 `1.10.0` 会被判成小于 `1.9.0`。
  ///
  /// Args:
  ///   currentVersionName: 已安装包的 versionName。
  ///   currentVersionCode: 已安装包的 versionCode。
  ///
  /// Returns:
  ///   清单版本更新时返回 true。
  bool isNewerThan({
    required String currentVersionName,
    required int currentVersionCode,
  }) {
    final int byName = compareVersionNames(versionName, currentVersionName);
    if (byName != 0) {
      return byName > 0;
    }
    return versionCode > currentVersionCode;
  }

  /// 是否能覆盖安装到指定 `versionCode` 的设备上。
  ///
  /// Android 安装器拒绝降级，所以即使语义版本更高，只要构建号不大于已装版本，
  /// 就不应拉起安装器，否则用户只会看到系统报错。
  bool canInstallOver(int currentVersionCode) =>
      versionCode > currentVersionCode;
}

/// 比较两个三段式版本号。
///
/// Args:
///   a: 版本号甲。
///   b: 版本号乙。
///
/// Returns:
///   `a > b` 返回正数，相等返回 0，`a < b` 返回负数；无法解析时按字符串比较兜底。
int compareVersionNames(String a, String b) {
  final List<int>? left = parseVersionName(a);
  final List<int>? right = parseVersionName(b);
  if (left == null || right == null) {
    return a.compareTo(b);
  }
  for (int i = 0; i < 3; i++) {
    final int diff = left[i] - right[i];
    if (diff != 0) {
      return diff;
    }
  }
  return 0;
}

/// 把 `major.minor.patch` 拆成三个整数。
///
/// Args:
///   value: 版本号字符串。
///
/// Returns:
///   长度固定为 3 的整数列表；格式不符时返回 null。
List<int>? parseVersionName(String value) {
  final List<String> parts = value.trim().split('.');
  if (parts.length != 3) {
    return null;
  }
  final List<int> numbers = <int>[];
  for (final String part in parts) {
    final int? number = int.tryParse(part);
    if (number == null || number < 0) {
      return null;
    }
    numbers.add(number);
  }
  return numbers;
}

/// 文件大小文案：B / KB / MB，保留一位小数。
///
/// Args:
///   bytes: 字节数。
///
/// Returns:
///   适合直接展示的字符串。
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

/// 读取必填整数字段；`true/false` 不算整数。
int _asInt(Map<String, dynamic> json, String field) {
  final Object? value = json[field];
  if (value is int) {
    return value;
  }
  if (value is double && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw ManifestFormatException(field, '缺少整数字段 $field');
}

/// 读取必填字符串字段。
String _asString(Map<String, dynamic> json, String field) {
  final Object? value = json[field];
  if (value is String) {
    return value;
  }
  throw ManifestFormatException(field, '缺少字符串字段 $field');
}
