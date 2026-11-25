import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';
import 'finance_shopping_manage_sheet.dart';
import 'finance_status_widgets.dart';

/// 购物记录：汇总（总额 / 平均单笔 / 涉及平台）+ 按平台消费 + 全部分页记录。
///
/// 数据（与网页端 `pages/finance/shopping.tsx` 调用一致）：
/// - `GET /finance/shopping/records?page=&page_size=20`
/// - `GET /finance/shopping/records/stats?days=3650`
/// - `GET /finance/shopping/platforms?page_size=100`（id → 平台名）
/// - `GET /finance/shopping/categories`（id → 分类名）
///
/// 写操作：点按记录进入编辑（保存 / 删除）；顶栏「维护」管理平台与分类。
class FinanceShoppingPage extends StatefulWidget {
  const FinanceShoppingPage({super.key});

  @override
  State<FinanceShoppingPage> createState() => _FinanceShoppingPageState();
}

class _FinanceShoppingPageState extends State<FinanceShoppingPage> {
  final List<ShoppingRecord> _items = <ShoppingRecord>[];
  final Map<int, String> _platforms = <int, String>{};
  final Map<int, String> _categories = <int, String>{};

  ShoppingStats? _stats;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 分类筛选：null 表示全部；切换后重新拉第一页，分页沿用筛选条件。
  int? _categoryFilter;

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

  /// 首屏/重试：并行拉汇总、第一页记录、平台与分类字典，任一失败整体进入失败态。
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
          .get<Map<String, dynamic>>(
            '/finance/shopping/records/stats',
            queryParameters: <String, dynamic>{'days': 3650},
          )
          .then((value) => value.data);
      final Future<Object?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/shopping/records',
            queryParameters: _listQuery(1),
          )
          .then((value) => value.data);
      final Future<Object?> platformFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/shopping/platforms',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data);
      final Future<Object?> categoryFuture = scope.apiClient
          .get<List<dynamic>>('/finance/shopping/categories')
          .then((value) => value.data);
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          statsFuture,
          listFuture,
          platformFuture,
          categoryFuture,
        ],
      );
      final Map<String, dynamic>? statsJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? listJson =
          responses[1] as Map<String, dynamic>?;
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '购物记录接口返回数据为空',
        );
      }
      final List<ShoppingRecord> items = _parseItems(listJson);
      final Map<int, String> platforms = _parseNamedOptions(responses[2]);
      final Map<int, String> categories =
          _parseCategoryNames(responses[3] as List<dynamic>?);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = ShoppingStats.fromJson(statsJson);
        _items
          ..clear()
          ..addAll(items);
        _platforms
          ..clear()
          ..addAll(platforms);
        _categories
          ..clear()
          ..addAll(categories);
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

  /// 加载更多：追加下一页；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/shopping/records',
                  queryParameters: _listQuery(_page + 1)))
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

  /// 列表查询参数：分类筛选只在选中时透传，未选中时后端返回全部。
  Map<String, dynamic> _listQuery(int page) {
    return <String, dynamic>{
      'page': page,
      'page_size': 20,
      if (_categoryFilter != null) 'category_id': _categoryFilter,
    };
  }

  /// 切换分类筛选：清空已加载分页并重新拉第一页。
  void _applyCategory(int? id) {
    if (_categoryFilter == id) {
      return;
    }
    setState(() {
      _categoryFilter = id;
      _items.clear();
      _hasMore = true;
      _status = LoadStatus.loading;
    });
    _refresh();
  }

  /// 分类筛选徽标：与报告生成页的 ChoiceChip 风格保持一致。
  Widget _categoryChip(int? id, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _categoryFilter == id,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => _applyCategory(id),
      ),
    );
  }

  /// 分页响应 `items` → [ShoppingRecord]。
  List<ShoppingRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => ShoppingRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 分页字典响应（platforms/ledgers）→ id → 名称映射。
  Map<int, String> _parseNamedOptions(Object? json) {
    final Map<int, String> result = <int, String>{};
    if (json is! Map<String, dynamic>) {
      return result;
    }
    for (final Map item
        in ((json['items'] as List?) ?? const <dynamic>[]).whereType<Map>()) {
      final NamedOption option =
          NamedOption.fromJson(item.cast<String, dynamic>());
      result[option.id] = option.name;
    }
    return result;
  }

  /// 分类数组响应 → id → 名称映射。
  Map<int, String> _parseCategoryNames(List<dynamic>? json) {
    final Map<int, String> result = <int, String>{};
    if (json == null) {
      return result;
    }
    for (final Map item in json.whereType<Map>()) {
      final Map<String, dynamic> data = item.cast<String, dynamic>();
      final int id = (data['id'] as num?)?.toInt() ?? -1;
      result[id] = data['name'] as String? ?? '';
    }
    return result;
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
    final AppTokens tokens = AppTokens.of(context);
    final ShoppingStats? stats = _stats;

    return DetailPageScaffold(
      title: '购物记录',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          if (stats != null) ...<Widget>[
            SummaryStrip(
              caption: '共 ${formatInt(stats.count)} 笔 · '
                  '涉及 ${formatInt(stats.byPlatform.length)} 个平台',
              items: <StatRailItem>[
                StatRailItem(
                  label: '消费总额',
                  value: formatInt(stats.total),
                  unit: '元',
                  color: tokens.red,
                ),
                StatRailItem(
                  label: '平均单笔',
                  value: formatInt(stats.average),
                  unit: '元',
                ),
                StatRailItem(
                  label: '涉及平台',
                  value: formatInt(stats.byPlatform.length),
                  unit: '个',
                ),
              ],
            ),
            if (stats.byPlatform.isNotEmpty) ...<Widget>[
              const SectionHeader(title: '按平台消费'),
              GroupCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: AmountBreakdownList(entries: stats.byPlatform),
                  ),
                ],
              ),
            ],
            if (_categories.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _categoryChip(null, '全部分类'),
                    for (final MapEntry<int, String> entry
                        in _categories.entries)
                      _categoryChip(entry.key, entry.value),
                  ],
                ),
              ),
            SectionHeader(
              title: _categoryFilter == null
                  ? '全部记录 · 共 ${formatInt(_total)} 条'
                  : '${_categories[_categoryFilter] ?? '筛选结果'} · 共 ${formatInt(_total)} 条',
              actionLabel: '新增记录',
              onAction: _openCreate,
            ),
            GroupCard(
              children: _items.isEmpty
                  ? const <Widget>[
                      EmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: '暂无购物记录',
                        description: '点「新增记录」录入第一笔消费',
                        compact: true,
                      ),
                    ]
                  : <Widget>[
                      for (final ShoppingRecord record in _items)
                        _ShoppingRow(
                          record: record,
                          platformName: record.platformLabel(_platforms),
                          categoryName: _categoryName(record.categoryId),
                          onTap: () => _openRecord(record),
                        ),
                    ],
            ),
            GroupCard(
              children: <Widget>[
                V2EntryRow(
                  title: '平台 / 分类维护',
                  subtitle: '新增或整理购物平台与消费分类',
                  icon: Icons.tune_outlined,
                  onTap: _manage,
                ),
              ],
            ),
            Text(
              '记录与网页端共用同一份数据；点按一条记录可编辑或删除。',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
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

  /// 分类 id → 名称；未设置分类时返回 null。
  String? _categoryName(int? id) {
    if (id == null) {
      return null;
    }
    final String? name = _categories[id];
    return (name == null || name.isEmpty) ? null : name;
  }

  /// 打开编辑页；保存或删除后返回 true，回到列表立即重算汇总。
  Future<void> _openRecord(ShoppingRecord record) async {
    final bool? changed = await context.push<bool>(
      '/finance/shopping/edit/${record.id}',
      extra: record,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 平台 / 分类维护；面板内改动后重载字典与汇总。
  Future<void> _manage() async {
    final bool? changed = await showShoppingManageSheet(context);
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 新增购物记录：保存成功返回 true 后重拉汇总与列表。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/finance/shopping/new');
    if (created == true && mounted) {
      await _refresh();
    }
  }
}

/// 单条购物记录：商品名 + 日期/平台/分类 + 总价（可选单价），点按进入编辑。
class _ShoppingRow extends StatelessWidget {
  const _ShoppingRow({
    required this.record,
    required this.platformName,
    required this.onTap,
    this.categoryName,
  });

  final ShoppingRecord record;
  final String platformName;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String meta = <String>[
      formatListDate(record.recordDate),
      platformName,
      ?categoryName,
    ].join(' · ');
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
                      record.productName,
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
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatMoney(record.totalPrice),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(color: tokens.text),
                  ),
                  if (record.unitPrice != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '单价 ${formatMoney(record.unitPrice)}',
                      maxLines: 1,
                      softWrap: false,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}
