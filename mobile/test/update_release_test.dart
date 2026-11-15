import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/core/update/release_info.dart';
import 'package:lifeos_mobile/core/update/update_service.dart';

Map<String, dynamic> _manifest({String sha256 = '', int size = 0}) {
  return <String, dynamic>{
    'manifest_version': 1,
    'platform': 'android',
    'version_name': '1.0.1',
    'version_code': 2009,
    'download_url': '/api/v1/downloads/LifeOS-1.0.1-2009.apk',
    'sha256': sha256.isEmpty ? 'a' * 64 : sha256,
    'size': size == 0 ? 1234 : size,
    'release_notes': '修复若干问题',
    'published_at': '2026-11-15T16:20:00+08:00',
    'min_android_sdk': 26,
  };
}

void main() {
  group('清单解析', () {
    test('合法清单逐字段读取', () {
      final ReleaseInfo info = ReleaseInfo.parse(_manifest());
      expect(info.versionName, '1.0.1');
      expect(info.versionCode, 2009);
      expect(info.size, 1234);
      expect(info.releaseNotes, '修复若干问题');
      expect(info.minAndroidSdk, 26);
    });

    test('SHA-256 非 64 位十六进制直接拒绝', () {
      expect(
        () => ReleaseInfo.parse(_manifest(sha256: 'abc')),
        throwsA(
          isA<ManifestFormatException>().having(
            (e) => e.field,
            'field',
            'sha256',
          ),
        ),
      );
    });

    test('版本号必须是三段式', () {
      final Map<String, dynamic> json = _manifest()..['version_name'] = '1.0';
      expect(
        () => ReleaseInfo.parse(json),
        throwsA(
          isA<ManifestFormatException>().having(
            (e) => e.field,
            'field',
            'version_name',
          ),
        ),
      );
    });

    test('平台不是 android 时拒绝', () {
      final Map<String, dynamic> json = _manifest()..['platform'] = 'ios';
      expect(
        () => ReleaseInfo.parse(json),
        throwsA(isA<ManifestFormatException>()),
      );
    });

    test('缺字段时拒绝', () {
      final Map<String, dynamic> json = _manifest()..remove('version_code');
      expect(
        () => ReleaseInfo.parse(json),
        throwsA(
          isA<ManifestFormatException>().having(
            (e) => e.field,
            'field',
            'version_code',
          ),
        ),
      );
    });
  });

  group('版本比较', () {
    test('按数值比较而非字符串', () {
      expect(compareVersionNames('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersionNames('1.0.0', '1.0.0'), 0);
      expect(compareVersionNames('2.0.0', '10.0.0'), lessThan(0));
    });

    test('语义版本相同再比构建号', () {
      final ReleaseInfo info = ReleaseInfo.parse(_manifest());
      expect(
        info.isNewerThan(currentVersionName: '1.0.1', currentVersionCode: 2008),
        isTrue,
      );
      expect(
        info.isNewerThan(currentVersionName: '1.0.1', currentVersionCode: 2009),
        isFalse,
      );
      expect(
        info.isNewerThan(currentVersionName: '1.0.2', currentVersionCode: 1),
        isFalse,
      );
    });

    test('构建号不大于已装版本时不允许覆盖安装', () {
      final ReleaseInfo info = ReleaseInfo.parse(_manifest());
      expect(info.canInstallOver(2008), isTrue);
      expect(info.canInstallOver(2009), isFalse);
      expect(info.canInstallOver(2010), isFalse);
    });
  });

  group('下载地址拼装', () {
    test('相对路径按服务器根地址补全', () {
      expect(
        UpdateService.resolveUrl(
          'http://192.168.8.103:9515/',
          '/api/v1/downloads/a.apk',
        ),
        'http://192.168.8.103:9515/api/v1/downloads/a.apk',
      );
      expect(
        UpdateService.resolveUrl('http://10.0.0.2:9515', 'x.apk'),
        'http://10.0.0.2:9515/x.apk',
      );
    });

    test('绝对地址原样使用', () {
      expect(
        UpdateService.resolveUrl('http://10.0.0.2:9515', 'https://cdn/a.apk'),
        'https://cdn/a.apk',
      );
    });
  });

  group('下载后校验', () {
    late HttpServer server;
    late Directory tempDir;
    late String base;
    final List<int> payload = utf8.encode('fake apk payload for update test');

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(payload);
        await request.response.close();
      });
      tempDir = await Directory.systemTemp.createTemp('lifeos_update_test');
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    ReleaseInfo releaseWith({required String sha, required int size}) {
      return ReleaseInfo.parse(_manifest(sha256: sha, size: size));
    }

    test('哈希与大小一致时落盘为正式文件', () async {
      final String sha = sha256.convert(payload).toString();
      final UpdateService service = UpdateService();
      final File file = await service.downloadApk(
        serverBase: base,
        release: releaseWith(sha: sha, size: payload.length),
        baseDir: tempDir,
      );
      expect(file.existsSync(), isTrue);
      expect(file.path.endsWith('.apk'), isTrue);
      expect(await file.length(), payload.length);
    });

    test('SHA-256 不一致时拒绝并删除临时文件', () async {
      final UpdateService service = UpdateService();
      await expectLater(
        service.downloadApk(
          serverBase: base,
          release: releaseWith(sha: 'b' * 64, size: payload.length),
          baseDir: tempDir,
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (e) => e.kind,
            'kind',
            UpdateFailureKind.hashMismatch,
          ),
        ),
      );
      final Directory updates = Directory('${tempDir.path}/updates');
      expect(
        updates.existsSync() ? updates.listSync().isEmpty : true,
        isTrue,
        reason: '校验失败后不能留下任何文件',
      );
    });

    test('大小不一致时拒绝并删除临时文件', () async {
      final String sha = sha256.convert(payload).toString();
      final UpdateService service = UpdateService();
      await expectLater(
        service.downloadApk(
          serverBase: base,
          release: releaseWith(sha: sha, size: payload.length + 1),
          baseDir: tempDir,
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (e) => e.kind,
            'kind',
            UpdateFailureKind.sizeMismatch,
          ),
        ),
      );
    });
  });

  group('下载取消', () {
    test('取消后抛 cancelled，且不留下文件', () async {
      // 服务端按块慢速输出，保证取消发生在传输过程中而不是下载完成之后
      final List<int> big = List<int>.filled(256 * 1024, 7);
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = big.length;
        for (int offset = 0; offset < big.length; offset += 4096) {
          request.response.add(big.sublist(offset, offset + 4096));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await request.response.close();
      });
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'lifeos_update_cancel',
      );
      final CancelToken token = CancelToken();
      final UpdateService service = UpdateService();
      final ReleaseInfo release = ReleaseInfo.parse(
        _manifest(sha256: sha256.convert(big).toString(), size: big.length),
      );
      try {
        await expectLater(
          service.downloadApk(
            serverBase: 'http://127.0.0.1:${server.port}',
            release: release,
            baseDir: tempDir,
            cancelToken: token,
            onProgress: (int received, int total) {
              if (received > 0 && !token.isCancelled) {
                token.cancel();
              }
            },
          ),
          throwsA(
            isA<UpdateFailure>().having(
              (e) => e.kind,
              'kind',
              UpdateFailureKind.cancelled,
            ),
          ),
        );
        final Directory updates = Directory('${tempDir.path}/updates');
        expect(
          updates.existsSync() ? updates.listSync().isEmpty : true,
          isTrue,
          reason: '取消后不能留下半截文件',
        );
      } finally {
        await server.close(force: true);
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
