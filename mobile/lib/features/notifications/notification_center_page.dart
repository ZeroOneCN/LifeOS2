import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/notification_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 通知中心：未读/总数概览 + 分页列表 + 全部标记已读。
///
/// 数据：
/// - `GET /notifications?page=&page_size=20`：通知列表（分页）；
/// - `GET /notifications/stats?days=365`：未读与总数概览；
/// - `PATCH /notifications/batch`：单条标记已读（只提交 `read`，不回写正文）；
/// - `POST /notifications/read-all`：全部标记已读。
///
/// 已读是写操作，直接请求服务端：失败时只提示「请重试」，
/// 不本地乐观标记，避免与服务端真实状态不一致。
class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  static const int _pageSize = 20;

  final List<AppNotification> _items = <AppNotification>[];
  final Set<int> _expanded = <int>{};

  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _unread = 0;
  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loadingMore = false;

  int? _markingId;
  bool _markingAll = false;

  /// 只看未读：后端列表接口不支持 `read` 过滤，这里对已加载页做本地筛选，
  /// 分页与「全部标记已读」保持原语义。
  bool _onlyUnread = false;

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

  /// 首屏/重试：并行拉未读概览与第一页列表；概览失败不阻塞列表。
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
      _status = _items.isEmpty ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Future<Map<String, dynamic>?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/notifications/stats',
            queryParameters: <String, dynamic>{'days': 365},
          )
          .then((value) => value.data)
          .catchError((Object _) => null);
      final Future<Map<String, dynamic>?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/notifications',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': _pageSize},
          )
          .then((value) => value.data);
      final List<Map<String, dynamic>?> responses =
          await Future.wait(<Future<Map<String, dynamic>?>>[
        statsFuture,
        listFuture,
      ]);
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      if (listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '通知接口返回数据为空',
        );
      }
      final List<AppNotification> items = _parseItems(listJson);
      final int unread = (statsJson?['unread'] as num?)?.toInt() ??
          items.where((AppNotification item) => !item.read).length;
      if (!mounted) {
        return;
      }
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _unread = unread;
        _page = 1;
        _total = (listJson['total'] as num?)?.toInt() ?? items.length;
        _hasMore = _items.length < _total;
        _expanded.clear();
        _status = LoadStatus.ready;
      });
      // 通知中心的未读数与顶栏角标共用同一份状态，读到即同步。
      scope.notifications.setCount(unread);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _errorStatus(scope, error);
        _message = error.message;
      });
    }
  }

  /// 加载更多：追加下一页；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/notifications',
                queryParameters: <String, dynamic>{
                  'page': _page + 1,
                  'page_size': _pageSize,
                },
              ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _page += 1;
        _items.addAll(_parseItems(json));
        _total = (json['total'] as num?)?.toInt() ?? _items.length;
        _hasMore = _items.length < _total;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载更多失败：${error.message}')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 点击通知：展开/收起正文；未读时尝试标记已读（失败只提示，不改本地状态）。
  void _onTap(AppNotification item) {
    setState(() {
      if (_expanded.contains(item.id)) {
        _expanded.remove(item.id);
      } else {
        _expanded.add(item.id);
      }
    });
    if (!item.read && _markingId == null) {
      _markRead(item);
    }
  }

  /// 单条标记已读：`PATCH /notifications/batch` 只写 `read` 字段。
  ///
  /// 不走 `PUT /notifications/{id}`：后者复用新增 schema，必须带 `title` /
  /// `category` / `notify_date` 等必填项，等于把客户端解码后的正文再回写一遍；
  /// 批量 PATCH 只 `setattr(read)`，从写入路径上杜绝正文被二次编码的可能。
  Future<void> _markRead(AppNotification item) async {
    final AppScope scope = AppScope.of(context);
    setState(() => _markingId = item.id);
    try {
      await scope.apiClient.patch<List<dynamic>>(
        '/notifications/batch',
        data: <String, dynamic>{
          'ids': <int>[item.id],
          'fields': <String, dynamic>{'read': true},
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final int index =
            _items.indexWhere((AppNotification row) => row.id == item.id);
        if (index >= 0) {
          _items[index] = _items[index].copyWith(read: true);
        }
        if (_unread > 0) {
          _unread -= 1;
        }
      });
      scope.notifications.setCount(_unread);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记已读失败：${error.message}，请重试')),
      );
    } finally {
      if (mounted) {
        setState(() => _markingId = null);
      }
    }
  }

  /// 全部标记已读：先确认再 `POST /notifications/read-all`，失败提示重试。
  Future<void> _markAllRead() async {
    if (_markingAll || _unread == 0) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('全部标记已读'),
          content: Text('将把 $_unread 条未读通知标记为已读，是否继续？'),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              second: AppPrimaryButton(
                label: '确定',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
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
    setState(() => _markingAll = true);
    try {
      await scope.apiClient.post<Map<String, dynamic>>(
        '/notifications/read-all',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        for (int i = 0; i < _items.length; i++) {
          if (!_items[i].read) {
            _items[i] = _items[i].copyWith(read: true);
          }
        }
        _unread = 0;
      });
      scope.notifications.setCount(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已全部标记为已读')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记失败：${error.message}，请重试')),
      );
    } finally {
      if (mounted) {
        setState(() => _markingAll = false);
      }
    }
  }

  /// 分页响应 `items` → [AppNotification]。
  List<AppNotification> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) =>
            AppNotification.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 列表页错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final List<AppNotification> visible = _onlyUnread
        ? _items.where((AppNotification item) => !item.read).toList()
        : _items;

    return DetailPageScaffold(
      title: '通知中心',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
              if (_status == LoadStatus.ready) ...<Widget>[
                // 分页之外补一个轻量筛选：只看未读（对已加载页生效）。
                Row(
                  spacing: 8,
                  children: <Widget>[
                    FilterChip(
                      label: const Text('全部'),
                      selected: !_onlyUnread,
                      onSelected: (_) => setState(() => _onlyUnread = false),
                    ),
                    FilterChip(
                      label: Text('未读 $_unread'),
                      selected: _onlyUnread,
                      onSelected: (_) => setState(() => _onlyUnread = true),
                    ),
                  ],
                ),
                SectionCard(
                  title: '全部通知',
                  trailing: Text(
                    _onlyUnread
                        ? '未读 ${visible.length} / 共 $_total 条'
                        : '共 $_total 条',
                    style: muted,
                  ),
                  child: visible.isEmpty
                      ? EmptyState(
                          icon: Icons.notifications_none,
                          title: _onlyUnread ? '没有未读通知' : '暂无通知',
                          description: _onlyUnread
                              ? (_items.isEmpty
                                  ? '系统与业务提醒会出现在这里'
                                  : '已加载的通知都已读，可切回「全部」')
                              : '系统与业务提醒会出现在这里',
                          compact: true,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 0,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '未读 $_unread 条',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: muted,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _unread == 0 || _markingAll
                                      ? null
                                      : _markAllRead,
                                  child: _markingAll
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('全部标记已读'),
                                ),
                              ],
                            ),
                            for (final AppNotification item in visible) ...<Widget>[
                              const Divider(height: 1),
                              _NotificationTile(
                                item: item,
                                expanded: _expanded.contains(item.id),
                                marking: _markingId == item.id,
                                onTap: () => _onTap(item),
                              ),
                            ],
                          ],
                        ),
                ),
                if (_items.isNotEmpty)
                  ListLoadMoreFooter(
                    loading: _loadingMore,
                    hasMore: _hasMore,
                    onPressed: _loadMore,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 单条通知：未读圆点 + 截断标题（长按显示全文）+ 类型/来源/日期 + 可展开正文。
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.expanded,
    required this.marking,
    required this.onTap,
  });

  final AppNotification item;
  final bool expanded;
  final bool marking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: muted);
    // 标题里已经带了日期（如「花呗2 2026-11-08 应还」），正文/摘要再写一遍
    // 「应还日期 2026-11-08」就是重复；同一日期只保留在正文与来源行里。
    final String body = _formatText(item.content ?? '');
    final String summary = _formatText(item.summary);
    final String title = _dedupeTitleDate(item.title, '$body$summary');
    final String content = _stripTitleDates(body, title);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.read
                          ? Colors.transparent
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: item.title,
                    child: Text(
                      title,
                      // 标题里带「平台 + 期次 + 日期」，1 行必被截断，给到 2 行。
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            item.read ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (marking)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: muted,
                    ),
                  ),
              ],
            ),
            // 元信息用 Wrap：窄屏 / 1.3x 字体下换行而不是溢出。
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item.category, style: metaStyle),
                ),
                if (item.sourceLabel != null)
                  Text('来源 ${item.sourceLabel}', style: metaStyle),
                Text(item.notifyDate, style: metaStyle),
              ],
            ),
            if (expanded) ...<Widget>[
              if (content.trim().isNotEmpty)
                Text(content, style: theme.textTheme.bodySmall),
              if (item.note != null && item.note!.trim().isNotEmpty)
                Text(
                  '备注：${_formatText(item.note!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ] else if (summary.isNotEmpty)
              Text(
                summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// 标题里的日期若在正文/摘要里也出现，就从标题里去掉：同一日期只说一次。
///
/// 只做「重复消除」，不做改写——正文与摘要里的日期原样保留，
/// 长按标题（Tooltip）仍显示后端原文。
String _dedupeTitleDate(String title, String body) {
  String output = title;
  for (final RegExpMatch match
      in RegExp(r'\d{4}-\d{2}-\d{2}').allMatches(title)) {
    final String date = match[0]!;
    if (body.contains(date)) {
      output = output.replaceAll(date, '');
    }
  }
  return output
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s·，,；;]+'), '')
      .trim();
}

/// 去掉正文里与标题重复的日期，并清理因此留下的空白与孤立标点。
String _stripTitleDates(String text, String title) {
  if (text.isEmpty) {
    return text;
  }
  String output = text;
  for (final RegExpMatch match
      in RegExp(r'\d{4}-\d{2}-\d{2}').allMatches(title)) {
    final String date = match[0]!;
    output = output.replaceAll('应还日期 $date', '');
    output = output.replaceAll(date, '');
  }
  return output
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s·，,；;]+'), '')
      .trim();
}

/// 通知正文的展示归一：去字段名冒号 + 金额补千分位。
String _formatText(String text) => _groupAmounts(_normalizeFieldLabels(text));

/// 把后端模板里的「应还日：2026-11-08」这类字段名拼接改成自然语句。
///
/// 常见字段顺便补全称呼（应还日 → 应还日期），其余「两到六个汉字：」统一
/// 去掉冒号；半角时间「18:52」不受影响。
String _normalizeFieldLabels(String text) {
  if (text.isEmpty) {
    return text;
  }
  String output = text;
  const Map<String, String> display = <String, String>{
    '应还日：': '应还日期 ',
    '到期日：': '到期日期 ',
    '账单日：': '账单日期 ',
  };
  display.forEach((String key, String value) {
    output = output.replaceAll(key, value);
  });
  // 「待还 应还日：…」去掉冒号后会读成「待还 应还日期」，两个「还」叠在一起；
  // 前一个「待还」是状态词、后一个是字段名，去掉状态词更顺。
  output = output.replaceAll('待还 应还日期', '应还日期');
  return output.replaceAllMapped(
    RegExp(r'([\u4e00-\u9fa5]{2,6})：'),
    (Match match) => '${match[1]} ',
  );
}

/// 给正文里的 `¥1424.07` 补千分位（`¥1,424.07`），与账单/报告金额格式一致。
String _groupAmounts(String text) {
  if (text.isEmpty) {
    return text;
  }
  return text.replaceAllMapped(
    RegExp(r'¥\s*(\d{4,})(\.\d+)?'),
    (Match match) {
      final String digits = match[1]!;
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < digits.length; i++) {
        if (i > 0 && (digits.length - i) % 3 == 0) {
          buffer.write(',');
        }
        buffer.write(digits[i]);
      }
      return '¥$buffer${match[2] ?? ''}';
    },
  );
}
