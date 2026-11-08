import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_scope.dart';
import '../../core/models/report_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';

/// 导出报告 PDF：`GET {apiPath}/{id}/export` 取文件流 → 写缓存 → 系统分享面板。
///
/// 与网页端下载的是同一份后端生成的 PDF，不在客户端重排内容；
/// 文件名优先取 `Content-Disposition`（后端用 `filename*=UTF-8''…` 编码中文），
/// 取不到时回退成「报告名_编号.pdf」。
Future<void> exportReportPdf({
  required BuildContext context,
  required ReportSource source,
  required int reportId,
  required String reportTitle,
}) async {
  final AppScope scope = AppScope.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('正在生成 PDF…')));
  try {
    final Response<List<int>> response = await scope.apiClient.get<List<int>>(
      '${source.apiPath}/$reportId/export',
      options: Options(
        responseType: ResponseType.bytes,
        // 报告含大量表格时后端需要逐页排版，默认 15 秒可能不够。
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    final List<int>? bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '导出接口返回空文件',
      );
    }
    final String filename = _pdfFilename(
      response.headers,
      fallback: '${source.pageTitle}_$reportId.pdf',
    );
    final Directory base = await getTemporaryDirectory();
    final Directory dir = Directory('${base.path}/lifeos_reports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
        subject: filename,
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('已导出 $filename（${_sizeText(bytes.length)}）')),
    );
  } on ApiException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('导出失败：${error.message}')));
  } on FileSystemException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('写入文件失败：${error.message}')));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
  }
}

/// 二次确认并删除报告；删除成功返回 true，取消或失败返回 false。
///
/// 报告是生成时快照，删除只影响历史列表计数与后续查看，不动业务数据；
/// 弹窗里写明这一点，避免用户误以为会回滚原始记录。
Future<bool> deleteReport({
  required BuildContext context,
  required ReportSource source,
  required int reportId,
  required String reportTitle,
  required String rangeText,

  /// 当前列表总数；未知时传 null，弹窗不写数量结论。
  required int? total,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('删除这份报告？'),
        content: Text(
          '将删除「${rangeText.isEmpty ? reportTitle : rangeText}」。\n'
          '${total == null ? '' : '删除后历史报告由 $total 份变为 ${total > 0 ? total - 1 : 0} 份，'}'
          '该份报告无法恢复；'
          '原始业务数据不受影响，需要时可重新生成。',
        ),
        actions: <Widget>[
          AppActionRow(
            first: AppSecondaryButton(
              label: '取消',
              compact: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            second: AppDangerButton(
              label: '删除',
              compact: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
        ],
      );
    },
  );
  if (confirmed != true) {
    return false;
  }
  if (!context.mounted) {
    return false;
  }
  final AppScope scope = AppScope.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    await scope.apiClient.delete<dynamic>('${source.apiPath}/$reportId');
    messenger.showSnackBar(const SnackBar(content: Text('已删除该份报告')));
    return true;
  } on ApiException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('删除失败：${error.message}')));
    return false;
  }
}

/// 从响应头解析文件名：先认 RFC 5987 的 `filename*=UTF-8''…`，再退回普通 `filename=`。
String _pdfFilename(Headers headers, {required String fallback}) {
  final String? raw = headers.value('content-disposition');
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  final RegExpMatch? encoded = RegExp(
    r"filename\*=UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(raw);
  final String? value =
      encoded?.group(1)?.trim() ??
      RegExp(
        r'filename="?([^";]+)"?',
        caseSensitive: false,
      ).firstMatch(raw)?.group(1)?.trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

/// 文件大小文案：KB / MB，保留一位小数。
String _sizeText(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
