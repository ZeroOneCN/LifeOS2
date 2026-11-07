import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 数据备份：管理员导出整库备份并保存到手机（仅下载，不做恢复导入）。
///
/// 后端契约（`backend/app/api/routes/backup.py`）：
/// - `POST /backup/export`，请求 `{tables, format, compress}`；
///   `tables=null` 表示全部表；`format` 为 `json|sql`；`compress` 仅对 JSON 生效。
/// - 响应是文件流（`Content-Disposition: attachment; filename=...`），不是路径。
/// - 全库 JSON / SQL 实测约 2–3 MB；移动端不提供按表勾选与站点级参数。
///
/// 落地方式：下载到应用缓存目录后调系统分享面板（share_plus），由用户
/// 自行保存到「文件」或发送给自己；不静默写入用户看不见的目录。
class BackupExportPage extends StatefulWidget {
  const BackupExportPage({super.key});

  @override
  State<BackupExportPage> createState() => _BackupExportPageState();
}

class _BackupExportPageState extends State<BackupExportPage> {
  /// 导出格式：json / sql / zip（zip = JSON 压缩）。
  String _format = 'json';

  bool _busy = false;
  int _received = 0;
  int _total = 0;
  String? _error;

  File? _lastFile;
  String? _lastFilename;
  int _lastSize = 0;
  DateTime? _lastAt;

  /// 备份日志（只读）：`GET /backup/logs`，按时间倒序分页。
  final List<_BackupLog> _logs = <_BackupLog>[];
  int _logsTotal = 0;
  int _logsPage = 0;
  bool _logsLoading = false;
  bool _logsLoadingMore = false;
  String? _logsError;

  @override
  void initState() {
    super.initState();
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (AppScope.of(context).auth.user?.isAdmin ?? false) {
        _loadLogs();
      }
    });
  }

  /// 拉取备份日志：`more=false` 重新拉第 1 页，`more=true` 追加下一页。
  Future<void> _loadLogs({bool more = false}) async {
    if (more && (_logsLoadingMore || _logs.length >= _logsTotal)) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final int nextPage = more ? _logsPage + 1 : 1;
    setState(() {
      if (more) {
        _logsLoadingMore = true;
      } else {
        _logsLoading = true;
        _logsError = null;
      }
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/backup/logs',
                  queryParameters: <String, dynamic>{
            'page': nextPage,
            'page_size': 10,
          }))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '备份日志接口返回数据为空',
        );
      }
      final List<_BackupLog> items =
          ((json['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map item) =>
                  _BackupLog.fromJson(item.cast<String, dynamic>()))
              .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        if (more) {
          _logs.addAll(items);
        } else {
          _logs
            ..clear()
            ..addAll(items);
        }
        _logsPage = nextPage;
        _logsTotal = (json['total'] as num?)?.toInt() ?? _logs.length;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _logsError = error.kind == ApiErrorKind.forbidden
            ? '无查看权限：备份日志仅管理员可见'
            : '备份日志读取失败：${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _logsLoading = false;
          _logsLoadingMore = false;
        });
      }
    }
  }

  /// 导出并保存：请求文件流 → 写缓存 → 打开系统分享面板。
  Future<void> _export() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _busy = true;
      _received = 0;
      _total = 0;
      _error = null;
    });
    try {
      final bool compress = _format == 'zip';
      final String requestFormat = _format == 'zip' ? 'json' : _format;
      final Response<List<int>> response =
          await scope.apiClient.post<List<int>>(
        '/backup/export',
        data: <String, dynamic>{
          'tables': null,
          'format': requestFormat,
          'compress': compress,
        },
        options: Options(
          responseType: ResponseType.bytes,
          // 服务端需先序列化整库再开始返回，局域网实测数秒内完成；
          // 给 2 分钟余量，避免默认 15 秒在大库上误判超时。
          receiveTimeout: const Duration(minutes: 2),
        ),
        onReceiveProgress: (int received, int total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      final List<int>? bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '导出接口返回空文件',
        );
      }
      final String filename = _filenameFromHeaders(response.headers, _format);
      final Directory base = await getTemporaryDirectory();
      final Directory dir = Directory('${base.path}/lifeos_backups');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // 仅保留最近一次导出，避免缓存目录无限增长。
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // 旧文件被系统占用时跳过，不影响本次导出
          }
        }
      }
      final File file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastFile = file;
        _lastFilename = filename;
        _lastSize = bytes.length;
        _lastAt = DateTime.now();
        _busy = false;
      });
      await _share(file, filename);
      if (!mounted) {
        return;
      }
      _snack('已导出 $filename（${_formatBytes(bytes.length)}），请在分享面板选择保存位置');
      // 本次导出会在服务端新增一条「手动导出」日志，立即重拉第一页。
      await _loadLogs();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = _hint(error);
      });
    } on FileSystemException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '写入文件失败：${error.message}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '导出失败：$error';
      });
    }
  }

  /// 调系统分享面板；失败只提示，不清除已下载的文件。
  Future<void> _share(File file, String filename) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: _mimeType(filename))],
          subject: 'LifeOS 数据备份 $filename',
          text: 'LifeOS 数据备份：$filename',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _snack('文件已下载，但打开系统分享失败：$error');
    }
  }

  /// 重新分享最近一次导出的文件。
  Future<void> _shareLast() async {
    final File? file = _lastFile;
    final String? filename = _lastFilename;
    if (file == null || filename == null) {
      return;
    }
    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _lastFile = null;
          _lastFilename = null;
          _error = '上次导出的文件已被系统清理，请重新导出';
        });
      }
      return;
    }
    await _share(file, filename);
  }

  /// 接口错误 → 可读原因；403 明确说明需要管理员权限。
  String _hint(ApiException error) {
    switch (error.kind) {
      case ApiErrorKind.forbidden:
        return '无导出权限：该接口仅管理员可用，请切换管理员账号';
      case ApiErrorKind.network:
        return '网络不可用，无法连接服务器；请检查 Wi-Fi 与服务器地址';
      case ApiErrorKind.timeout:
        return '请求超时：请检查 Wi-Fi 与服务器是否可达；'
            '若网络正常但数据量较大，可重试或在网页端导出';
      case ApiErrorKind.server:
        return '服务器导出失败，请稍后重试（详情见网页端备份日志）';
      case ApiErrorKind.unauthorized:
        return '登录状态已失效，请重新登录后再导出';
      default:
        return error.message;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final bool loggedIn = scope.auth.isLoggedIn;
    final bool isAdmin = scope.auth.user?.isAdmin ?? false;

    return DetailPageScaffold(
      title: '数据备份',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              if (!loggedIn)
                ListStatusView(
                  status: scope.auth.connectionFailed
                      ? LoadStatus.connectionFailed
                      : LoadStatus.unauthenticated,
                  message: scope.auth.restoreError,
                  onRetry: scope.auth.restore,
                )
              else if (!isAdmin)
                _PermissionNotice(
                  account: scope.auth.user?.account ?? '',
                )
              else ...<Widget>[
                SectionCard(
                  title: '导出范围',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: <Widget>[
                      Text(
                        '移动端只做整库导出与下载，不支持按表勾选、定时备份、'
                        '备份清理与恢复导入；这些操作请在网页端「系统 → 数据备份」中完成。',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      Text(
                        '每次导出会在网页端备份日志中留下一条「手动导出」记录。',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '导出设置',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      SegmentedButton<String>(
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(value: 'json', label: Text('JSON')),
                          ButtonSegment<String>(value: 'sql', label: Text('SQL')),
                          ButtonSegment<String>(value: 'zip', label: Text('ZIP')),
                        ],
                        selected: <String>{_format},
                        showSelectedIcon: false,
                        onSelectionChanged: _busy
                            ? null
                            : (Set<String> selection) {
                                setState(() => _format = selection.first);
                              },
                      ),
                      Text(
                        _formatHint(_format),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      if (_busy) ...<Widget>[
                        LinearProgressIndicator(
                          value: _total > 0 ? _received / _total : null,
                        ),
                        Text(
                          _total > 0
                              ? '正在导出与下载 ${(_received * 100 / _total).toStringAsFixed(0)}%'
                                  '（${_formatBytes(_received)} / ${_formatBytes(_total)}）'
                              : '正在导出：服务端正在生成备份，请稍候…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                      FilledButton.icon(
                        onPressed: _busy ? null : _export,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(_busy ? '正在导出…' : '导出并保存'),
                      ),
                      Text(
                        '导出完成后会打开系统分享面板，可保存到「文件」或发送给自己。',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                if (_lastFile != null) ...<Widget>[
                  SectionCard(
                    title: '上次导出',
                    trailing: TextButton(
                      onPressed: _shareLast,
                      child: const Text('再次分享'),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 6,
                      children: <Widget>[
                        Text(
                          _lastFilename ?? '',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_formatBytes(_lastSize)} · '
                          '${_displayTime(_lastAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                        Text(
                          '文件临时保存在应用缓存目录（系统文件管理器中不可见），'
                          '请通过系统分享保存到本地；重新导出会覆盖上一份临时文件。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SectionCard(
                  title: '备份日志',
                  trailing: Text(
                    _logsTotal > 0 ? '共 $_logsTotal 条' : '只读',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: _logsLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 4,
                          children: <Widget>[
                            if (_logsError != null)
                              Text(
                                _logsError!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              )
                            else if (_logs.isEmpty)
                              Text(
                                '暂无备份日志',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                              )
                            else
                              for (final _BackupLog log in _logs)
                                _LogRow(log: log),
                            if (_logs.length < _logsTotal)
                              _logsLoadingMore
                                  ? const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: () => _loadLogs(more: true),
                                      child: Text(
                                        '加载更多（已显示 ${_logs.length} / $_logsTotal）',
                                      ),
                                    )
                            else if (_logs.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  '已显示全部 $_logsTotal 条',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: muted),
                                ),
                              ),
                            const Divider(height: 16),
                            Text(
                              '日志只读：可查看时间、类型、结果与文件大小；'
                              '清理日志、恢复导入请在网页端操作。',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: muted),
                            ),
                          ],
                        ),
                ),
                Text(
                  'SQL 含表结构与数据，适合完整迁移；JSON 适合网页端导入；'
                  'ZIP 为 JSON 压缩包，使用前需先解压。移动端不做恢复导入，避免误覆盖线上数据。',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 非管理员提示：明确说明无权限，不提供点了没反应的按钮。
class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.account});

  final String account;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return SectionCard(
      title: '无导出权限',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 28, color: muted),
          Text(
            '当前账号${account.isEmpty ? '' : '（$account）'}不是管理员，不能导出数据备份。',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '请使用管理员账号登录，或在网页端「系统 → 数据备份」中操作。'
            '本页不会发起任何导出请求。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// 一条备份日志（只读展示用）：`GET /backup/logs` 的 `items` 项。
class _BackupLog {
  const _BackupLog({
    required this.id,
    required this.name,
    required this.exportFormat,
    required this.filename,
    required this.fileSizeDisplay,
    required this.status,
    required this.errorMessage,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String exportFormat;
  final String? filename;
  final String? fileSizeDisplay;
  final String status;
  final String? errorMessage;
  final DateTime? createdAt;

  /// 解析接口项；缺字段时给安全默认值，不因单条异常影响整个列表。
  factory _BackupLog.fromJson(Map<String, dynamic> json) {
    return _BackupLog(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      exportFormat: (json['export_format'] as String?) ?? '',
      filename: json['filename'] as String?,
      fileSizeDisplay: json['file_size_display'] as String?,
      status: (json['status'] as String?) ?? 'success',
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '')
          ?.toLocal(),
    );
  }

  bool get succeeded => status == 'success';
}

/// 日志行：`#id · 时间 · 类型` + `格式 · 大小 · 文件名`，失败时附原因。
class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});

  final _BackupLog log;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String format = log.exportFormat.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: <Widget>[
          Row(
            spacing: 8,
            children: <Widget>[
              Text(
                '#${log.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  _displayTime(log.createdAt),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              if (log.name.isNotEmpty)
                Expanded(
                  flex: 2,
                  child: Text(
                    log.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              Text(
                log.succeeded ? '成功' : '失败',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: log.succeeded
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ),
          Text(
            '${format.isEmpty ? '' : '$format · '}'
            '${log.fileSizeDisplay ?? '—'}'
            '${log.filename == null ? '' : ' · ${log.filename}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (!log.succeeded &&
              log.errorMessage != null &&
              log.errorMessage!.trim().isNotEmpty)
            Text(
              log.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

/// 格式说明文案。
String _formatHint(String format) {
  switch (format) {
    case 'sql':
      return 'SQL：含表结构与数据，适合完整迁移；由后端 mysqldump 或纯 Python 生成。';
    case 'zip':
      return 'ZIP：JSON 数据压缩包，体积更小，使用前需先解压。';
    default:
      return 'JSON：导出全部表的数据内容，可通过网页端备份导入恢复。';
  }
}

/// 从 `Content-Disposition` 解析文件名；缺失时按格式生成兜底文件名。
String _filenameFromHeaders(Headers headers, String format) {
  final String? raw = headers.value('content-disposition');
  if (raw != null) {
    final RegExpMatch? match = RegExp(r'filename="?([^";]+)"?').firstMatch(raw);
    final String? value = match?.group(1);
    if (value != null && value.isNotEmpty) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }
  }
  final DateTime now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final String stamp = '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return format == 'sql' ? 'sql_$stamp.sql' : 'full_$stamp.json';
}

/// 按扩展名给分享面板一个 MIME 类型。
String _mimeType(String filename) {
  if (filename.endsWith('.zip')) {
    return 'application/zip';
  }
  if (filename.endsWith('.sql')) {
    return 'application/sql';
  }
  return 'application/json';
}

/// 文件大小：B / KB / MB，保留一位小数。
String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  double value = bytes / 1024;
  if (value < 1024) {
    return '${value.toStringAsFixed(1)} KB';
  }
  value /= 1024;
  return '${value.toStringAsFixed(1)} MB';
}

/// 导出时间：本地 `MM-dd HH:mm`。
String _displayTime(DateTime? time) {
  if (time == null) {
    return '—';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
