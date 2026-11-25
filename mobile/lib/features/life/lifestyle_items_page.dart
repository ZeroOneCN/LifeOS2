import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';
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
    final AppTokens tokens = AppTokens.of(context);
    final ItemStats? stats = _stats;

    return DetailPageScaffold(
      title: '物品追踪',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          if (stats != null) ...<Widget>[
            SummaryStrip(
              caption: '使用中 ${formatInt(stats.inUse)} 件 · '
                  '日均成本 ${formatMoney(stats.avgDailyCost)} · '
                  '总价值 ${formatMoney(stats.totalValue)}',
              items: <StatRailItem>[
                StatRailItem(
                  label: '物品总数',
                  value: formatInt(stats.total),
                  unit: '件',
                ),
                StatRailItem(
                  label: '临期',
                  value: formatInt(stats.expiring),
                  unit: '件',
                  color: tokens.orange,
                ),
                StatRailItem(
                  label: '已过期',
                  value: formatInt(stats.expired),
                  unit: '件',
                  color: tokens.red,
                ),
              ],
            ),
            if (stats.byStatus.isNotEmpty) ...<Widget>[
              const SectionHeader(title: '状态分布'),
              GroupCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final LabelCount entry in stats.byStatus)
                          V2Badge(
                            '${itemStatusLabel(entry.label)} '
                            '${formatInt(entry.count)}',
                            tone: _statusTone(entry.label),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            SectionHeader(
              title: '全部物品 · 共 ${formatInt(_total)} 件',
              actionLabel: '新增物品',
              onAction: _openCreate,
            ),
            GroupCard(
              children: <Widget>[
                if (_items.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: '暂无物品',
                    description: '点「新增物品」录入第一件',
                    compact: true,
                  )
                else
                  for (final LifestyleItem item in _items)
                    _ItemRow(item: item, onTap: () => _openEdit(item)),
              ],
            ),
          ],
        ],
        footer: _items.isNotEmpty
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

/// 物品状态 → 徽标色调：使用中绿色、借出橙色、丢失红色、回收灰色。
V2BadgeTone _statusTone(String status) {
  switch (status) {
    case 'in_use':
      return V2BadgeTone.green;
    case 'loaned':
      return V2BadgeTone.warn;
    case 'lost':
      return V2BadgeTone.danger;
    default:
      return V2BadgeTone.gray;
  }
}

/// 单件物品：名称 + 购买日期/分类/位置 → 价格与到期徽标。
///
/// 到期日为空的物品不显示任何临期/过期标记，避免把「未填」误判为过期。
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final LifestyleItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ItemExpiry? expiry = item.expiryInfo();
    final String meta = <String>[
      if ((item.purchaseDate ?? '').isNotEmpty)
        '购入 ${formatListDate(item.purchaseDate)}',
      if (item.category.trim().isNotEmpty) item.category.trim(),
      if ((item.location ?? '').trim().isNotEmpty) item.location!.trim(),
      if (item.status != 'in_use') itemStatusLabel(item.status),
      if ((item.expireDate ?? '').isNotEmpty)
        '到期 ${formatListDate(item.expireDate)}',
    ].join(' · ');
    final bool showExpiry = expiry != null && expiry.daysLeft <= 30;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    if (meta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowMeta.copyWith(color: tokens.text2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatMoney(item.price),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(
                      color:
                          item.price == null ? tokens.text3 : tokens.text,
                    ),
                  ),
                  if (showExpiry) ...<Widget>[
                    const SizedBox(height: 4),
                    V2Badge(
                      _expiryLabel(expiry),
                      tone: expiry.isExpired
                          ? V2BadgeTone.danger
                          : V2BadgeTone.warn,
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }

  /// 到期文案：过期 / 今天 / 剩余天数。
  static String _expiryLabel(ItemExpiry expiry) {
    if (expiry.isExpired) {
      return '已过期 ${-expiry.daysLeft} 天';
    }
    if (expiry.daysLeft == 0) {
      return '今天到期';
    }
    return '剩 ${expiry.daysLeft} 天';
  }
}
