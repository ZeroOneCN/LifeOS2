import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/notification_models.dart';
import '../../core/network/api_exception.dart';
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
/// 取舍：已读是写操作，但**不接离线队列**——已读状态滞后不致命，
/// 失败时只提示「请重试」，不占用队列额度、也不引入跨端覆盖风险。
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定'),
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
                SectionCard(
                  title: '全部通知',
                  trailing: Text('共 $_total 条', style: muted),
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.notifications_none,
                          title: '暂无通知',
                          description: '系统与业务提醒会出现在这里',
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
                            for (final AppNotification item in _items) ...<Widget>[
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
    final String content = item.content ?? '';

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
                      item.title,
                      maxLines: 1,
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
                if (item.source != null && item.source!.isNotEmpty)
                  Text('来源 ${item.source}', style: metaStyle),
                Text(item.notifyDate, style: metaStyle),
              ],
            ),
            if (expanded) ...<Widget>[
              if (content.trim().isNotEmpty)
                Text(content, style: theme.textTheme.bodySmall),
              if (item.note != null && item.note!.trim().isNotEmpty)
                Text(
                  '备注：${item.note}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ] else if (item.summary.isNotEmpty)
              Text(
                item.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      ),
    );
  }
}
