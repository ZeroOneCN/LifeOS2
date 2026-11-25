import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/report_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';
import 'report_actions.dart';

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载更多失败：${error.message}')));
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
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            widget.source.apiPath,
            queryParameters: <String, dynamic>{
              'page': page,
              'page_size': _pageSize,
            },
          )).data;
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
      final List<dynamic>? data = (await scope.apiClient.get<List<dynamic>>(
        widget.source.apiPath,
      )).data;
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
    final bool offline =
        scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  /// 生成报告：表单成功返回新报告 id 后刷新列表并直接打开明细。
  Future<void> _openGenerate() async {
    final int? id = await context.push<int>(widget.source.generateRoute);
    if (id == null || !mounted) {
      return;
    }
    await _refresh();
    if (!mounted) {
      return;
    }
    await context.push<bool>('${widget.source.routeBase}/$id');
    if (mounted) {
      await _refresh();
    }
  }

  /// 导出单份报告为 PDF（后端生成，客户端只负责下载与分享）。
  Future<void> _export(ReportSummaryItem item) {
    return exportReportPdf(
      context: context,
      source: widget.source,
      reportId: item.id,
      reportTitle: _rowTitle(item),
    );
  }

  /// 删除单份报告：二次确认后删除并刷新列表。
  Future<void> _delete(ReportSummaryItem item) async {
    final bool deleted = await deleteReport(
      context: context,
      source: widget.source,
      reportId: item.id,
      reportTitle: _rowTitle(item),
      rangeText: item.rangeText,
      total: _total,
    );
    if (deleted && mounted) {
      await _refresh();
    }
  }

  /// 行标题：优先统计区间，其次报告名，最后编号。
  String _rowTitle(ReportSummaryItem item) {
    if (item.rangeText.isNotEmpty) {
      return item.rangeText;
    }
    return item.displayTitle.isNotEmpty ? item.displayTitle : '报告 #${item.id}';
  }

  /// 打开明细；明细页删除报告后返回 true，需要刷新列表。
  Future<void> _openDetail(ReportSummaryItem item) async {
    final bool? changed = await context.push<bool>(
      '${widget.source.routeBase}/${item.id}',
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReportSummaryItem? latest = _items.isEmpty ? null : _items.first;
    // 指标格宽度有限，只放「月-日」；完整生成时间仍在行内副标题里。
    final Match? match = RegExp(
      r'\d{4}-(\d{2}-\d{2})',
    ).firstMatch(latest?.createdAt ?? '');

    return DetailPageScaffold(
      title: widget.source.pageTitle,
      bottomBar: AppPrimaryButton(
        label: '生成报告',
        icon: Icons.auto_awesome_outlined,
        onPressed: _openGenerate,
      ),
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          SummaryStrip(
            items: <StatRailItem>[
              StatRailItem(label: '报告总数', value: '$_total', unit: '份'),
              StatRailItem(
                label: '最近生成',
                value: match == null ? '—' : match[1]!,
              ),
            ],
          ),
          const SectionHeader(title: '历史报告'),
          if (_items.isEmpty)
            GroupCard(
              children: <Widget>[
                EmptyState(
                  icon: Icons.description_outlined,
                  title: '暂无报告',
                  description: widget.source.emptyDescription,
                  compact: true,
                  actionLabel: '生成报告',
                  onAction: _openGenerate,
                ),
              ],
            )
          else
            GroupCard(
              children: <Widget>[
                for (final ReportSummaryItem item in _items)
                  _ReportRow(
                    item: item,
                    onOpen: () => _openDetail(item),
                    onExport: () => _export(item),
                    onDelete: () => _delete(item),
                  ),
              ],
            ),
        ],
        footer: widget.source.listPaginated && _items.isNotEmpty
            ? ListLoadMoreFooter(
                loading: _loadingMore,
                hasMore: _hasMore,
                onPressed: _loadMore,
              )
            : null,
      ),
    );
  }
}

/// 单条报告：统计区间作标题（同类型报告靠区间区分），生成时间作副标题。
///
/// 之前标题固定为报告名，同页多份报告标题完全一样，只能靠小字区间猜；
/// 页面标题已经标明报告类型，行内再重复一次没有信息量。
class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.item,
    required this.onOpen,
    required this.onExport,
    required this.onDelete,
  });

  final ReportSummaryItem item;
  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String title = item.rangeText.isNotEmpty
        ? item.rangeText
        : (item.displayTitle.isNotEmpty ? item.displayTitle : '报告 #${item.id}');
    final String meta = item.createdText.isNotEmpty
        ? item.createdText
        : '编号 #${item.id}';
    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 17,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ),
              ),
              // 导出 / 删除收进菜单，避免每行堆两个按钮。
              PopupMenuButton<String>(
                tooltip: '报告操作',
                icon: Icon(Icons.more_vert, size: 18, color: tokens.text3),
                onSelected: (String value) {
                  if (value == 'export') {
                    onExport();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'export',
                    child: Text('导出 PDF'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      '删除',
                      style: TextStyle(color: tokens.red),
                    ),
                  ),
                ],
              ),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}
