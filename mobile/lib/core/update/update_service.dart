import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'release_info.dart';

/// 更新失败的原因分类。
///
/// 每一种都要落到不同的用户提示上：连不上服务器、清单坏了、校验不符、
/// 安装权限没开、用户取消，不能统一成「请求失败」。
enum UpdateFailureKind {
  /// 网络不可达 / 超时。
  network,

  /// 服务器还没有发布清单（404 release_not_found）。
  notPublished,

  /// 清单字段缺失或格式非法（500 manifest_invalid，或客户端解析失败）。
  manifestInvalid,

  /// 下载过程中断（非用户取消）。
  downloadFailed,

  /// 下载大小与清单不一致。
  sizeMismatch,

  /// SHA-256 与清单不一致。
  hashMismatch,

  /// 本地文件写入失败（空间不足、目录不可写）。
  storage,

  /// 系统未授予「安装未知应用」权限。
  installPermission,

  /// 设备上没有可处理安装包的 Activity。
  installerMissing,

  /// 用户主动取消。
  cancelled,

  /// 兜底。
  unknown,
}

/// 更新流程中的可读错误。
class UpdateFailure implements Exception {
  const UpdateFailure(this.kind, this.message, {this.hint = ''});

  final UpdateFailureKind kind;

  /// 主提示，一句话说清发生了什么。
  final String message;

  /// 建议动作，可为空。
  final String hint;

  @override
  String toString() => message;
}

/// 版本清单拉取与 APK 下载 / 校验。
///
/// 清单接口匿名可读，所以这里用独立的 [Dio]，不接入带 401 刷新的 ApiClient；
/// 下载走同一个 Dio 的长超时实例。
class UpdateService {
  UpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              sendTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 20),
              // 清单与 APK 都由我们自己的后端返回，不做重定向跟随之外的额外处理
              followRedirects: true,
              maxRedirects: 3,
            ),
          );

  final Dio _dio;

  /// 清单路径（相对 `/api/v1` 前缀）。
  static const String manifestPath = '/app/releases/android';

  /// 应用仓库根地址：团队统一发布渠道，优先从这里检查更新。
  static const String storeBase = 'https://apps.01iot.top';

  /// 应用仓库使用的包名（与 `android/app/build.gradle` 的 applicationId 一致）。
  static const String storePackageName = 'com.lifeos.mobile';

  /// 从应用仓库检查更新（`GET /api/update/check`，公开接口）。
  ///
  /// Args:
  ///   versionCode: 当前安装包的构建号，服务端按整数比较。
  ///
  /// Returns:
  ///   有新版本时返回仓库里的最新版本；已是最新时返回 null。
  ///
  /// Throws:
  ///   UpdateFailure: `notPublished` 表示应用尚未在仓库上架（调用方回退自建清单），
  ///   其他为网络不可达或响应异常。
  Future<ReleaseInfo?> fetchFromStore({required int versionCode}) async {
    final String url = Uri.parse('$storeBase/api/update/check')
        .replace(
          queryParameters: <String, String>{
            'packageName': storePackageName,
            'versionCode': '$versionCode',
          },
        )
        .toString();
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>(
            url,
            options: Options(
              responseType: ResponseType.json,
              headers: <String, dynamic>{'Cache-Control': 'no-cache'},
            ),
          );
      final Map<String, dynamic>? data = response.data;
      if (data == null || data['hasUpdate'] != true) {
        return null;
      }
      final Object? latest = data['latest'];
      if (latest is! Map<String, dynamic>) {
        throw const UpdateFailure(
          UpdateFailureKind.manifestInvalid,
          '应用仓库没有返回最新版本信息',
        );
      }
      return ReleaseInfo.fromStore(latest);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const UpdateFailure(
          UpdateFailureKind.notPublished,
          '应用仓库未上架该应用',
        );
      }
      throw _mapDioException(error, url);
    } on ManifestFormatException catch (error) {
      throw UpdateFailure(
        UpdateFailureKind.manifestInvalid,
        '应用仓库版本信息解析失败：${error.message}',
        hint: '出错字段 ${error.field}',
      );
    }
  }

  /// 把更新服务器地址与清单里的下载地址拼成绝对地址。
  ///
  /// Args:
  ///   serverBase: 更新服务器根地址，形如 `http://192.168.8.103:9515`（不含 `/api/v1`）。
  ///   downloadUrl: 清单里的下载地址，可能是绝对地址或以 `/` 开头的相对路径。
  ///
  /// Returns:
  ///   可直接请求的绝对地址。
  static String resolveUrl(String serverBase, String downloadUrl) {
    final String value = downloadUrl.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final String base = serverBase.trim().replaceFirst(RegExp(r'/+$'), '');
    return value.startsWith('/') ? '$base$value' : '$base/$value';
  }

  /// 拉取并解析版本清单。
  ///
  /// Args:
  ///   serverBase: 更新服务器根地址（不含 `/api/v1`）。
  ///
  /// Returns:
  ///   解析后的清单。
  ///
  /// Throws:
  ///   UpdateFailure: 网络不可达、服务器未发布、清单非法。
  Future<ReleaseInfo> fetchManifest(String serverBase) async {
    final String base = serverBase.trim().replaceFirst(RegExp(r'/api/v1$'), '');
    final String url =
        '${base.replaceFirst(RegExp(r'/+$'), '')}/api/v1$manifestPath';
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>(
            url,
            options: Options(
              responseType: ResponseType.json,
              // 清单每次都可能是新发布的版本，绕开中间缓存
              headers: <String, dynamic>{'Cache-Control': 'no-cache'},
            ),
          );
      final Map<String, dynamic>? data = response.data;
      if (data == null) {
        throw const UpdateFailure(
          UpdateFailureKind.manifestInvalid,
          '版本清单返回空内容',
          hint: '请检查服务器上的 android.json 是否为空文件',
        );
      }
      return ReleaseInfo.parse(data);
    } on DioException catch (error) {
      throw _mapDioException(error, url);
    } on ManifestFormatException catch (error) {
      throw UpdateFailure(
        UpdateFailureKind.manifestInvalid,
        '版本清单解析失败：${error.message}',
        hint: '出错字段 ${error.field}，请重新生成服务器上的 android.json',
      );
    }
  }

  /// 下载 APK 并校验大小与 SHA-256。
  ///
  /// 下载先写 `.part` 临时文件，校验通过后才改名为正式文件；任何一步失败都会
  /// 删除临时文件，绝不把未校验的包交给安装器。
  ///
  /// Args:
  ///   serverBase: 更新服务器根地址（用于补全相对下载地址）。
  ///   release: 目标版本清单。
  ///   baseDir: 应用私有外部目录（与 FileProvider 的 `external-files-path` 对应）。
  ///   onProgress: 已接收字节数与总字节数回调。
  ///   cancelToken: 取消令牌。
  ///
  /// Returns:
  ///   校验通过的 APK 文件。
  ///
  /// Throws:
  ///   UpdateFailure: 下载失败、大小/哈希不符、写盘失败或用户取消。
  Future<File> downloadApk({
    required String serverBase,
    required ReleaseInfo release,
    required Directory baseDir,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final String url = resolveUrl(serverBase, release.downloadUrl);
    final Directory dir = Directory('${baseDir.path}/updates');
    final File part = File('${dir.path}/${_fileNameFor(release)}.part');
    final File target = File(part.path.substring(0, part.path.length - 5));
    try {
      await dir.create(recursive: true);
      if (part.existsSync()) {
        await part.delete();
      }
      await _dio.download(
        url,
        part.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          // 63 MB 的通用包在局域网也要几十秒，不能用清单的 20 秒
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
    } on DioException catch (error) {
      await _safeDelete(part);
      if (error.type == DioExceptionType.cancel) {
        throw const UpdateFailure(UpdateFailureKind.cancelled, '已取消下载');
      }
      throw UpdateFailure(
        UpdateFailureKind.downloadFailed,
        '下载中断：${_describeDio(error)}',
        hint: '确认手机与服务器在同一网络后重试；已删除未完成的文件',
      );
    } on FileSystemException catch (error) {
      await _safeDelete(part);
      throw UpdateFailure(
        UpdateFailureKind.storage,
        '无法写入下载目录：${error.message}',
        hint: '检查手机可用存储空间后重试',
      );
    }

    try {
      final int actualSize = await part.length();
      if (actualSize != release.size) {
        await _safeDelete(part);
        throw UpdateFailure(
          UpdateFailureKind.sizeMismatch,
          '下载文件大小不符：期望 ${formatBytes(release.size)}，实际 ${formatBytes(actualSize)}',
          hint: '文件可能在传输中损坏，已删除；请重新下载',
        );
      }
      final String actualHash = await _sha256OfFile(part);
      if (actualHash != release.sha256.toLowerCase()) {
        await _safeDelete(part);
        throw UpdateFailure(
          UpdateFailureKind.hashMismatch,
          '安装包校验不通过（SHA-256 与清单不一致）',
          hint: '已删除下载文件，未拉起安装器；请确认服务器上的 APK 与清单是同一版本',
        );
      }
      if (target.existsSync()) {
        await target.delete();
      }
      return await part.rename(target.path);
    } on FileSystemException catch (error) {
      await _safeDelete(part);
      throw UpdateFailure(
        UpdateFailureKind.storage,
        '校验后写入失败：${error.message}',
        hint: '检查手机可用存储空间后重试',
      );
    }
  }

  /// 计算文件 SHA-256：流式读取，避免把 63 MB 一次性读进内存。
  Future<String> _sha256OfFile(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 删除临时文件，失败不覆盖原始错误。
  ///
  /// 多轮删除而不是一次：取消时 Dio 的文件写入器是异步关闭的，
  /// 刚删掉的文件可能被缓冲区再写回来（Windows 上还会因为句柄未释放直接失败）。
  Future<void> _safeDelete(File file) async {
    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        if (file.existsSync()) {
          await file.delete();
        }
      } on FileSystemException {
        // 句柄尚未释放，等下一轮
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 从下载地址里取文件名；取不到就用构建号兜底。
  String _fileNameFor(ReleaseInfo release) {
    final String path = Uri.tryParse(release.downloadUrl)?.path ?? '';
    final String name = path
        .split('/')
        .where((String s) => s.isNotEmpty)
        .fold('', (String _, String part) => part);
    if (name.isEmpty) {
      return 'LifeOS-${release.versionCode}.apk';
    }
    return name.endsWith('.apk') ? name : '$name.apk';
  }

  /// Dio 异常 → 可读失败原因（区分「服务器未发布」「清单非法」与网络问题）。
  UpdateFailure _mapDioException(DioException error, String url) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return UpdateFailure(
          UpdateFailureKind.network,
          '连接更新服务器超时',
          hint: '检查地址 $url 是否可达',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return UpdateFailure(
          UpdateFailureKind.network,
          '连不上更新服务器',
          hint: '确认手机与服务器在同一局域网，或在设置里修改更新服务器地址',
        );
      case DioExceptionType.badResponse:
        return _mapBadResponse(error, url);
      case DioExceptionType.cancel:
        return const UpdateFailure(UpdateFailureKind.cancelled, '已取消');
      case DioExceptionType.badCertificate:
        return const UpdateFailure(
          UpdateFailureKind.network,
          '服务器证书校验失败',
          hint: '局域网自签证书需要系统信任后才可访问',
        );
    }
  }

  /// 4xx/5xx 分流：404 是「还没发布」，500 且带 manifest_invalid 是「清单坏了」。
  UpdateFailure _mapBadResponse(DioException error, String url) {
    final int? status = error.response?.statusCode;
    final Object? data = error.response?.data;
    String? code;
    String? field;
    String? detailMessage;
    if (data is Map) {
      final Object? detail = data['detail'];
      if (detail is Map) {
        code = detail['code'] as String?;
        field = detail['field'] as String?;
        detailMessage = detail['message'] as String?;
      } else if (detail is String) {
        detailMessage = detail;
      }
    }
    if (status == 404) {
      return const UpdateFailure(
        UpdateFailureKind.notPublished,
        '服务器还没有发布版本清单',
        hint: '先执行 scripts/build_release_apk.ps1 生成 android.json 再检查更新',
      );
    }
    if (code == 'manifest_invalid' || status == 500) {
      return UpdateFailure(
        UpdateFailureKind.manifestInvalid,
        detailMessage ?? '服务器版本清单不合法（HTTP $status）',
        hint: field == null ? '请重新生成 android.json' : '出错字段 $field',
      );
    }
    return UpdateFailure(
      UpdateFailureKind.unknown,
      '更新服务器返回 HTTP $status',
      hint: url,
    );
  }

  /// 下载异常的一句话描述。
  String _describeDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '连接超时';
      case DioExceptionType.connectionError:
        return '无法连接服务器';
      case DioExceptionType.badResponse:
        return 'HTTP ${error.response?.statusCode}';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '已取消';
      case DioExceptionType.unknown:
        return error.message ?? '未知错误';
    }
  }
}
