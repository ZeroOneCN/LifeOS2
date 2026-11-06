import 'dart:io';

import 'package:dio/dio.dart';

import '../auth/auth_service.dart';
import '../network/api_client.dart';

/// 头像上传/设置的客户端校验结果：返回 null 表示通过，否则为中文提示。
class AvatarRules {
  const AvatarRules._();

  /// 服务端上限：2 MB。
  static const int maxBytes = 2097152;

  /// 服务端允许的后缀。
  static const Set<String> allowedExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
  };

  /// 校验本地文件（类型 + 体积），与后端规则保持一致，避免等服务端 413。
  static String? validateFile(File file) {
    final int size = file.lengthSync();
    if (size > maxBytes) {
      final String mb = (size / 1024 / 1024).toStringAsFixed(2);
      return '图片不能超过 2 MB（当前 $mb MB），请重新选择';
    }
    final String name = file.path.split(Platform.pathSeparator).last;
    final String ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!allowedExtensions.contains(ext)) {
      return '仅支持 png / jpg / jpeg / webp 格式';
    }
    return null;
  }

  /// 校验外链：仅 http/https，长度 ≤ 255。
  static String? validateUrl(String url) {
    final String value = url.trim();
    if (value.isEmpty) {
      return '请填写图片地址';
    }
    if (value.length > 255) {
      return '图片地址不能超过 255 个字符';
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return '仅支持 http / https 图片地址';
    }
    return null;
  }
}

/// 头像接口封装：
/// - `POST /user/avatar`（multipart，字段 `file`）；
/// - `PUT /user/avatar`（JSON `{"avatar_url": ...}`，传 null 清空）；
/// - 两个写接口成功后统一用 `GET /user/profile` 回读，保证多处显示一致。
class ProfileService {
  ProfileService(this._api, this._auth);

  final ApiClient _api;
  final AuthService _auth;

  /// 上传本地图片，返回服务端的 `avatar` 字段。
  ///
  /// [onProgress] 为 dio 的发送进度（sent / total 字节）。
  Future<String?> uploadAvatar(
    File file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final String name = file.path.split(Platform.pathSeparator).last;
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        file.path,
        filename: name,
        contentType: _mediaType(name),
      ),
    });
    final Map<String, dynamic>? data = (await _api
            .postMultipart<Map<String, dynamic>>(
      '/user/avatar',
      data: form,
      onSendProgress: (int sent, int total) => onProgress?.call(sent, total),
    ))
        .data;
    await _auth.refreshProfile();
    return data?['avatar'] as String?;
  }

  /// 设置外链头像；[url] 为 null 表示清空。
  Future<String?> setAvatarUrl(String? url) async {
    final Map<String, dynamic>? data = (await _api.put<Map<String, dynamic>>(
      '/user/avatar',
      data: <String, dynamic>{'avatar_url': url},
    ))
        .data;
    await _auth.refreshProfile();
    return data?['avatar'] as String?;
  }

  static DioMediaType? _mediaType(String name) {
    switch (name.split('.').last.toLowerCase()) {
      case 'png':
        return DioMediaType('image', 'png');
      case 'webp':
        return DioMediaType('image', 'webp');
      case 'jpeg':
      case 'jpg':
        return DioMediaType('image', 'jpeg');
      default:
        return null;
    }
  }
}
