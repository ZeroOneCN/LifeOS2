import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../../theme/app_theme.dart';
import 'lifestyle_item_form_page.dart';

/// 物品追踪：汇总（数量 / 价值 / 临期 / 过期）+ 状态分布 + 物品分页。
///
/// 数据（与网页端 `pages/lifestyle/items.tsx` 调用一致）：
/// - `GET /lifestyle/items?page=&page_size=20`
/// - `GET /lifestyle/items/stats?days=30`
class LifestyleItemsPage extends StatefulWidget {
  const LifestyleItemsPage({super.key});

  @override
  State<LifestyleItemsPage> createState() => _LifestyleItemsPageState();
}

class _LifestyleItemsPageState extends State<LifestyleItemsPage> {
  final List<LifestyleItem> _items = <LifestyleItem>[];

  ItemStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 首屏 / 重试：并行拉汇总与第一页物品。
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
      _status = _stats == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Future<Object?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/items/stats',
              queryParameters: <String, dynamic>{'days': 30})
          .then((value) => value.data);
      final Future<Object?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>('/lifestyle/items',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 20})
          .then((value) => value.data);
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[statsFuture, listFuture],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '物品接口返回数据为空',
        );
      }
      final List<LifestyleItem> items = _parseItems(listJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = ItemStats.fromJson(statsJson);
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _total = (listJson['total'] as num?)?.toInt() ?? items.length;
        _hasMore = _items.length < _total;
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

  /// 加载更多：追加下一页物品。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/lifestyle/items',
                  queryParameters: <String, dynamic>{
            'page': _page + 1,
            'page_size': 20,
          }))
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

  /// 分页响应 `items` → [LifestyleItem]。
  List<LifestyleItem> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) =>
            LifestyleItem.fromJson(item.cast<String, dynamic>()))
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

  /// 分类下拉选项：来自统计接口 `by_category`，过滤空分类。
  List<String> get _categories {
    return ((_stats?.byCategory ?? const <LabelCount>[]))
        .map((LabelCount item) => item.label)
        .where((String label) => label.trim().isNotEmpty)
        .toList();
  }

  /// 打开新增页；保存成功后重拉统计与第一页列表。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>(
      '/life/items/new',
      extra: LifestyleItemFormArgs(categories: _categories),
    );
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 打开编辑页；保存或删除后重拉，让状态分布与合计同步。
  Future<void> _openEdit(LifestyleItem item) async {
    final bool? changed = await context.push<bool>(
      '/life/items/edit/${item.id}',
      extra: LifestyleItemFormArgs(item: item, categories: _categories),
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ItemStats? stats = _stats;

    return DetailPageScaffold(
      title: '物品追踪',
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
              if (_status == LoadStatus.ready && stats != null) ...<Widget>[
                SectionCard(
                  title: '合计',
                  trailing: Text(
                    '近 30 天临期口径',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Column(
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: MetricPlaceholder(
                              label: '物品总数',
                              value: formatInt(stats.total),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '使用中',
                              value: formatInt(stats.inUse),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '总价值',
                              value: formatMoney(stats.totalValue),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: MetricPlaceholder(
                              label: '日均成本',
                              value: formatMoney(stats.avgDailyCost),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '临期',
                              value: formatInt(stats.expiring),
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '已过期',
                              value: formatInt(stats.expired),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (stats.byStatus.isNotEmpty)
                  SectionCard(
                    title: '状态分布',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final LabelCount item in stats.byStatus)
                          _CountChip(
                            label: itemStatusLabel(item.label),
                            count: item.count,
                          ),
                      ],
                    ),
                  ),
                SectionCard(
                  title: '全部物品',
                  trailing: AppPrimaryAction(
                    label: '新增物品',
                    onPressed: _openCreate,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: <Widget>[
                      if (_total > 0)
                        Text(
                          '共 $_total 条 · 按购买日期倒序',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_items.isEmpty)
                        const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: '暂无物品',
                          description: '点右上角「新增物品」录入第一件',
                          compact: true,
                        )
                      else
                        Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final LifestyleItem item in _items)
                              _ItemRow(
                                item: item,
                                onTap: () => _openEdit(item),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (_items.isNotEmpty)
                  _LoadMoreFooter(
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

/// 状态分布小标签：`使用中 374`。
class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label ${formatInt(count)}',
        maxLines: 1,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

/// 单件物品：名称 + 购买日期/分类/位置 + 价格与到期提示。
///
/// 到期日为空的物品不显示任何临期/过期标记，避免把「未填」误判为过期。
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final LifestyleItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final TextStyle? metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: muted);
    final ItemExpiry? expiry = item.expiryInfo();
    final List<Widget> meta = <Widget>[
      if (item.purchaseDate != null && item.purchaseDate!.isNotEmpty)
        Text('购入 ${item.purchaseDate}', style: metaStyle),
      if (item.category.isNotEmpty) Text(item.category, style: metaStyle),
      if (item.location != null && item.location!.isNotEmpty)
        Text(item.location!, style: metaStyle),
      if (item.status != 'in_use')
        Text(itemStatusLabel(item.status), style: metaStyle),
      if (item.expireDate != null && item.expireDate!.isNotEmpty)
        Text('到期 ${item.expireDate}', style: metaStyle),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: <Widget>[
                  Text(
                    item.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  // 元信息用 Wrap：窄屏 / 1.3x 字体下换行而不是省略号截断。
                  Wrap(spacing: 8, runSpacing: 2, children: meta),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: <Widget>[
                Text(
                  formatMoney(item.price),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                if (expiry != null)
                  _ExpiryLabel(expiry: expiry, style: metaStyle),
              ],
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 到期提示：已过期为红色、30 天内临期为橙色，更远则不显示。
class _ExpiryLabel extends StatelessWidget {
  const _ExpiryLabel({required this.expiry, this.style});

  final ItemExpiry expiry;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final int left = expiry.daysLeft;
    if (left > 30) {
      return const SizedBox.shrink();
    }
    final Color color = expiry.isExpired
        ? context.semanticColors.danger
        : context.semanticColors.warning;
    final String text = expiry.isExpired
        ? '已过期 ${-left} 天'
        : (left == 0 ? '今天到期' : '还剩 $left 天');
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: style?.copyWith(color: color),
    );
  }
}

/// 列表页「加载更多 / 已全部加载」页脚（与 B3 列表一致的交互）。
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.hasMore,
    required this.onPressed,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '已加载全部',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return TextButton(onPressed: onPressed, child: const Text('加载更多'));
  }
}
