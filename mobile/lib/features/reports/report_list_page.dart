import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/report_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 报告列表页：财务 / 投资 / 健康 / 生活报告共用，按 [ReportSource] 区分数据源。
///
/// 接口：`GET {source.apiPath}`。财务/投资/生活返回报告数组，
/// 健康返回分页对象 `{items,total}`（按 20 份一页加载更多）。
/// 行内标题只放报告名，统计区间放在副标题，且只出现一次。
class ReportListPage extends StatefulWidget {
  const ReportListPage({super.key, required this.source});

  final ReportSource source;

  @override
  State<ReportListPage> createState() => _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> {
  static const int _pageSize = 20;

  final List<ReportSummaryItem> _items = <ReportSummaryItem>[];
  LoadStatus _status = LoadStatus.loading;
  String? _message;
  int _page = 1;
  int _total = 0;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 拉取第一页报告；空数组进入空态，网络异常按离线/未登录分流。
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
      final List<ReportSummaryItem> items = await _fetchPage(1);
      if (!mounted) {
        return;
      }
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        if (!widget.source.listPaginated) {
          _total = items.length;
        }
        _hasMore = widget.source.listPaginated && _items.length < _total;
        _status = LoadStatus.ready;
      });
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

  /// 加载下一页：追加并保留已加载数据；失败只提示，不清空列表。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final List<ReportSummaryItem> items = await _fetchPage(_page + 1);
      if (!mounted) {
        return;
      }
      setState(() {
        _page += 1;
        _items.addAll(items);
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

  /// 请求指定页：分页接口取 `items/total`，数组接口一次性返回全部。
  Future<List<ReportSummaryItem>> _fetchPage(int page) async {
    final AppScope scope = AppScope.of(context);
    final List<ReportSummaryItem> items;
    if (widget.source.listPaginated) {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
        widget.source.apiPath,
        queryParameters: <String, dynamic>{
          'page': page,
          'page_size': _pageSize,
        },
      ))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '报告接口返回数据为空',
        );
      }
      final List<dynamic> rows = json['items'] as List<dynamic>? ?? <dynamic>[];
      _total = (json['total'] as num?)?.toInt() ?? rows.length;
      items = rows
          .whereType<Map>()
          .map(
            (Map item) =>
                ReportSummaryItem.fromJson(item.cast<String, dynamic>()),
          )
          .toList();
    } else {
      final List<dynamic>? data =
          (await scope.apiClient.get<List<dynamic>>(widget.source.apiPath))
              .data;
      if (data == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '报告接口返回数据为空',
        );
      }
      items = data
          .whereType<Map>()
          .map(
            (Map item) =>
                ReportSummaryItem.fromJson(item.cast<String, dynamic>()),
          )
          .toList();
    }
    return items;
  }

  /// 错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
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
    final TextStyle? trailingStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DetailPageScaffold(
      title: widget.source.pageTitle,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
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
              if (_status == LoadStatus.ready)
                SectionCard(
                  title: '历史报告',
                  trailing: Text('共 $_total 份', style: trailingStyle),
                  child: _items.isEmpty
                      ? EmptyState(
                          icon: Icons.description_outlined,
                          title: '暂无报告',
                          description: widget.source.emptyDescription,
                          compact: true,
                        )
                      : Column(
                          children: <Widget>[
                            for (final ReportSummaryItem item in _items)
                              _ReportRow(source: widget.source, item: item),
                            if (widget.source.listPaginated)
                              ListLoadMoreFooter(
                                loading: _loadingMore,
                                hasMore: _hasMore,
                                onPressed: _loadMore,
                              ),
                          ],
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单条报告：标题（仅报告名）+ 副标题（区间）+ 生成时间。
class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.source, required this.item});

  final ReportSource source;
  final ReportSummaryItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return InkWell(
      onTap: () => context.push('${source.routeBase}/${item.id}'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          spacing: 10,
          children: <Widget>[
            Icon(Icons.description_outlined, size: 20, color: muted),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: <Widget>[
                  Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 区间与生成时间放同一行 Wrap：1.3x 下换行而不是截断。
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: <Widget>[
                      if (item.rangeText.isNotEmpty)
                        Text(item.rangeText, style: metaStyle),
                      if (item.createdText.isNotEmpty)
                        Text(item.createdText, style: metaStyle),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}
