import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

/// 登录设备：列出当前账号的活跃会话，支持下线其他设备（只读列表 + 单台下线）。
///
/// 数据来源（后端 `auth.py`）：
/// - `GET /auth/sessions`：会话列表（设备标识、IP、登录/活跃时间、是否当前设备）；
/// - `DELETE /auth/sessions/{id}`：删除该会话的刷新令牌，使其立即失效。
///
/// 当前设备通过 access token 里的 `sid` 判定；当前设备不允许在本页下线，
/// 避免用户误操作把自己登出（退出请走设置页「退出」）。
class DeviceSessionsPage extends StatefulWidget {
  const DeviceSessionsPage({super.key});

  @override
  State<DeviceSessionsPage> createState() => _DeviceSessionsPageState();
}

class _DeviceSessionsPageState extends State<DeviceSessionsPage> {
  List<_LoginSession>? _sessions;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  /// 正在下线的会话 id，避免重复点击。
  int? _revokingId;

  /// 设备搜索关键字（匹配设备名 / 系统摘要 / IP / 最近活跃时间）。
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 读取 access token 里的 `sid`（会话 id）。
  ///
  /// 只解析 JWT 载荷用于界面标记，不校验签名；服务端仍会校验令牌与会话。
  Future<int?> _currentSessionId(AppScope scope) async {
    final String? access = await scope.tokenStore.readAccessToken();
    if (access == null || access.isEmpty) {
      return null;
    }
    final List<String> parts = access.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final String payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return (decoded['sid'] as num?)?.toInt();
      }
    } catch (_) {
      // 载荷不是合法 base64/JSON 时不阻塞列表，交给服务端标记兜底
    }
    return null;
  }

  /// 拉取会话列表；失败按登录态/网络/接口错误分流。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _status = scope.auth.connectionFailed
            ? LoadStatus.connectionFailed
            : LoadStatus.unauthenticated;
        _message = scope.auth.restoreError;
      });
      return;
    }
    setState(() {
      _status = _sessions == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    final int? sid = await _currentSessionId(scope);
    // 载荷解析不出 sid 时退回后端约定：用 refresh_token 标记当前会话。
    final String? fallbackToken =
        sid == null ? await scope.tokenStore.readRefreshToken() : null;
    try {
      final List<dynamic>? data = (await scope.apiClient.get<List<dynamic>>(
        '/auth/sessions',
        queryParameters: fallbackToken == null
            ? null
            : <String, dynamic>{'current_token': fallbackToken},
      ))
          .data;
      if (data == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '会话接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = data
            .whereType<Map>()
            .map((Map<dynamic, dynamic> item) =>
                _LoginSession.fromJson(item.cast<String, dynamic>()))
            .map((_LoginSession item) => sid == null
                ? item
                : item.copyWith(isCurrent: item.id == sid))
            .toList();
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final bool offline = scope.auth.hasLocalSession &&
          (error.kind == ApiErrorKind.network ||
              error.kind == ApiErrorKind.timeout);
      setState(() {
        _status = error.isUnauthorized
            ? LoadStatus.unauthenticated
            : (offline ? LoadStatus.connectionFailed : LoadStatus.failed);
        _message = error.message;
      });
    }
  }

  /// 确认后下线指定会话；成功后刷新列表。
  Future<void> _revoke(_LoginSession session) async {
    // 确认弹窗使用完整设备标识（含长 UA），确保用户能准确判断要下线的设备。
    final String target = (session.device ?? '').trim();
    final String targetName = target.isEmpty ? '未知设备' : target;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('下线该设备'),
          content: Text(
            '确定下线「$targetName」吗？\n'
            '该设备会立即退出登录，需要重新登录后才能继续访问。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppDangerButton(
                label: '确认下线',
                icon: Icons.logout,
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _revokingId = session.id);
    try {
      await scope.apiClient.delete<void>('/auth/sessions/${session.id}');
      if (!mounted) {
        return;
      }
      _snack('已下线「${_deviceLabel(session.device)}」');
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.kind == ApiErrorKind.notFound) {
        _snack('该会话已不存在，列表已刷新');
        await _refresh();
      } else {
        _snack('下线失败：${error.message}');
      }
    } finally {
      if (mounted) {
        setState(() => _revokingId = null);
      }
    }
  }

  /// 二次确认后一次性下线其余所有设备；本机会话由后端按 refresh_token 保留。
  Future<void> _revokeOthers() async {
    final int others =
        (_sessions ?? const <_LoginSession>[]).where((_LoginSession s) => !s.isCurrent).length;
    if (others == 0) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('下线其他所有设备'),
          content: Text(
            '将下线除当前设备外的 $others 个登录会话。\n'
            '这些设备会立即退出登录，需要重新登录。\n'
            '当前设备不受影响。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppDangerButton(
                label: '确认全部下线',
                icon: Icons.phonelink_erase,
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _revokingId = -1);
    try {
      await scope.auth.revokeOtherSessions();
      if (!mounted) {
        return;
      }
      _snack('已下线其余 $others 个设备');
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _snack('批量下线失败：${error.message}');
    } finally {
      if (mounted) {
        setState(() => _revokingId = null);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<_LoginSession> all = _sessions ?? const <_LoginSession>[];
    final String query = _query.trim().toLowerCase();
    final List<_LoginSession> sessions = query.isEmpty
        ? all
        : all.where((_LoginSession session) {
            final String haystack = <String>[
              _deviceLabel(session.device),
              _deviceDetail(session.device) ?? '',
              session.ip ?? '',
              _displayTime(session.lastUsedAt),
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          }).toList();
    final int others =
        all.where((_LoginSession session) => !session.isCurrent).length;

    return DetailPageScaffold(
      title: '登录设备',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          SummaryStrip(
            items: <StatRailItem>[
              StatRailItem(label: '登录会话', value: '${all.length}'),
              StatRailItem(label: '当前设备', value: '${all.length - others}'),
              StatRailItem(
                label: '其他设备',
                value: '$others',
                color: others > 0 ? tokens.orange : null,
              ),
            ],
          ),
          // 会话多时（实测 29 台）没有搜索只能逐条翻；按设备名 / IP /
          // 最近活跃时间过滤。
          V2SearchField(
            controller: _search,
            hint: '搜索设备名、IP 或时间',
            onChanged: (String value) => setState(() => _query = value),
          ),
          SectionHeader(
            title: query.isEmpty
                ? '活跃会话（${all.length}）'
                : '活跃会话（${sessions.length} / ${all.length}）',
            actionLabel: '刷新',
            onAction: _refresh,
          ),
          if (sessions.isEmpty)
            GroupCard(
              children: <Widget>[
                EmptyState(
                  icon: Icons.devices_other,
                  title: query.isEmpty ? '暂无活跃会话' : '没有匹配的设备',
                  description: query.isEmpty
                      ? '当前账号没有可显示的登录会话'
                      : '换个关键字，或点搜索框右侧清空',
                  compact: true,
                ),
              ],
            )
          else
            GroupCard(
              children: <Widget>[
                for (final _LoginSession session in sessions)
                  _SessionRow(
                    session: session,
                    revoking: _revokingId == session.id,
                    onRevoke: _revokingId == null
                        ? () => _revoke(session)
                        : null,
                  ),
              ],
            ),
          // 会话多时逐条下线成本高：后端 `revoke-others` 以当前 refresh_token
          // 识别本机会话，只清理其余设备，不会把本机踢下线。
          if (others > 0)
            AppSecondaryButton(
              label: '下线其他所有设备（$others）',
              icon: Icons.phonelink_erase,
              onPressed: _revokingId == null ? _revokeOthers : null,
            ),
          Text(
            '当前设备不能在这里下线，如需退出请到设置页点「退出」。'
            '时间以服务器记录为准。',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
        ],
      ),
    );
  }
}

/// 单条会话：设备标识 + 当前设备标记 + IP/时间 +（非当前设备的）下线按钮。
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.revoking,
    required this.onRevoke,
  });

  final _LoginSession session;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String label = _deviceLabel(session.device);
    // 原始 UA 很长，1.3x 下只能显示半截；改展示解析后的「浏览器 · 系统」摘要，
    // 完整 UA 仍保留在下线确认弹窗里，需要核对时可以看全。
    final String? detail = _deviceDetail(session.device);
    final Color markColor = session.isCurrent ? tokens.accent : tokens.text2;
    final TextStyle metaStyle = AppType.statLabel.copyWith(color: tokens.text3);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: markColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              session.isCurrent ? Icons.smartphone : Icons.devices_other,
              size: 17,
              color: markColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowTitle.copyWith(color: tokens.text),
                      ),
                    ),
                    if (session.isCurrent) ...<Widget>[
                      const SizedBox(width: 6),
                      const V2Badge('当前设备', tone: V2BadgeTone.info),
                    ],
                  ],
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: AppType.rowMeta.copyWith(
                      color: tokens.text2,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: <Widget>[
                    Text('最近活跃：${_displayTime(session.lastUsedAt)}', style: metaStyle),
                    Text('登录于：${_displayTime(session.createdAt)}', style: metaStyle),
                    Text('IP：${_maskIp(session.ip)}', style: metaStyle),
                    Text('会话 #${session.id}', style: metaStyle),
                  ],
                ),
              ],
            ),
          ),
          if (!session.isCurrent) ...<Widget>[
            const SizedBox(width: 8),
            AppDangerButton(
              label: revoking ? '下线中…' : '下线',
              icon: Icons.logout,
              compact: true,
              loading: revoking,
              onPressed: onRevoke,
            ),
          ],
        ],
      ),
    );
  }
}

/// IP 脱敏展示：列表不直接暴露完整地址。
///
/// IPv4 保留前两段（`192.168.1.23` → `192.168.*.*`）；其他格式只留前 8 位。
/// 搜索仍按完整 IP 匹配，脱敏只影响展示。
String _maskIp(String? raw) {
  final String value = (raw ?? '').trim();
  if (value.isEmpty) {
    return '—';
  }
  final List<String> parts = value.split('.');
  if (parts.length == 4) {
    return '${parts[0]}.${parts[1]}.*.*';
  }
  return value.length > 8 ? '${value.substring(0, 8)}…' : value;
}

/// 后端会话记录：`created_at` / `last_used_at` 原样保留为字符串。
class _LoginSession {
  const _LoginSession({
    required this.id,
    this.device,
    this.ip,
    this.createdAt,
    this.lastUsedAt,
    this.isCurrent = false,
  });

  factory _LoginSession.fromJson(Map<String, dynamic> json) {
    return _LoginSession(
      id: (json['id'] as num?)?.toInt() ?? 0,
      device: json['device'] as String?,
      ip: json['ip_address'] as String?,
      createdAt: json['created_at'] as String?,
      lastUsedAt: json['last_used_at'] as String?,
      isCurrent: json['is_current'] as bool? ?? false,
    );
  }

  final int id;
  final String? device;
  final String? ip;
  final String? createdAt;
  final String? lastUsedAt;
  final bool isCurrent;

  _LoginSession copyWith({bool? isCurrent}) {
    return _LoginSession(
      id: id,
      device: device,
      ip: ip,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}

/// 会话时间展示：`YYYY-MM-DDTHH:mm:ss` → `MM-dd HH:mm`（省略年份，节省窄屏宽度）；
/// 缺失显示「—」。
String _displayTime(String? value) {
  if (value == null || value.isEmpty) {
    return '—';
  }
  final String text = value.replaceFirst('T', ' ');
  return text.length >= 16
      ? '${text.substring(5, 10)} ${text.substring(11, 16)}'
      : text;
}

/// 设备标识 → 可读名称；无法归类时截断展示原始标识。
String _deviceLabel(String? device) {
  final String raw = (device ?? '').trim();
  if (raw.isEmpty) {
    return '未知设备';
  }
  if (raw.contains('Dart/')) {
    return '移动端 App';
  }
  if (raw.toLowerCase().contains('curl')) {
    return 'curl 客户端';
  }
  if (raw.contains('WindowsPowerShell') || raw.contains('PowerShell')) {
    return 'PowerShell';
  }
  if (raw.contains('TraeCN')) {
    return 'Trae 内置浏览器';
  }
  if (raw.contains('Chrome')) {
    return raw.contains('Android') ? 'Chrome（手机）' : 'Chrome（PC）';
  }
  if (raw.contains('Safari')) {
    return 'Safari';
  }
  return raw.length > 24 ? '${raw.substring(0, 24)}…' : raw;
}

/// 从 UA 提取可读摘要（浏览器版本 · 系统），用于替代被截断的原始 UA。
///
/// 解析不出任何信息时返回 null，宁可不显示，也不展示半截机器串。
String? _deviceDetail(String? device) {
  final String raw = (device ?? '').trim();
  if (raw.isEmpty) {
    return null;
  }
  final List<String> parts = <String>[];
  final Match? chrome = RegExp(r'Chrome/(\d+)').firstMatch(raw);
  if (chrome != null) {
    parts.add('Chrome ${chrome[1]}');
  } else if (raw.contains('Safari') && !raw.contains('Chrome')) {
    parts.add('Safari');
  }
  final Match? windows = RegExp(r'Windows NT ([\d.]+)').firstMatch(raw);
  if (windows != null) {
    // 摘要行只有一行，「Windows 10/11 · Chrome 155」在 1.3x 下仍会截断；
    // 系统名保持「Windows」即可，版本对识别设备没有帮助。
    const Map<String, String> names = <String, String>{
      '10.0': 'Windows',
      '6.3': 'Windows',
      '6.2': 'Windows',
      '6.1': 'Windows',
    };
    parts.add(names[windows[1]] ?? 'Windows');
  } else {
    final Match? android = RegExp(r'Android\s+([\d.]+)').firstMatch(raw);
    if (android != null) {
      parts.add('Android ${android[1]}');
    } else if (raw.contains('iPhone') || raw.contains('iPad')) {
      parts.add('iOS');
    } else if (raw.contains('Mac OS X')) {
      parts.add('macOS');
    } else if (raw.contains('Linux')) {
      parts.add('Linux');
    }
  }
  return parts.isEmpty ? null : parts.join(' · ');
}
