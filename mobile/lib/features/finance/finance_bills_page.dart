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
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_tokens.dart';
import 'finance_bill_detail_sheet.dart';
import 'finance_bill_form_page.dart';
import 'finance_repay_sheet.dart';
import 'finance_status_widgets.dart';

/// 账单管理：按网页端 `/finance/bills` 的三个 Tab 组织。
///
/// 数据（与网页端同源）：
/// - 网贷借还：`GET /finance/loan-bills/stats?days=0`、`GET /finance/loan-bills`
/// - 房租水电：`GET /finance/housing`、`GET /finance/utilities`
/// - 服务订阅：`GET /finance/subscriptions`
///
/// 三个 Tab 共用同一个纵向 ListView，切换只换内容，不产生横向滚动或栏位跳动。
class FinanceBillsPage extends StatefulWidget {
  const FinanceBillsPage({super.key});

  @override
  State<FinanceBillsPage> createState() => _FinanceBillsPageState();
}

class _FinanceBillsPageState extends State<FinanceBillsPage> {
  /// 0 网贷借还、1 房租水电、2 服务订阅。
  int _tab = 0;

  final List<BillItem> _items = <BillItem>[];

  /// 未来月份的账单：服务端只按 `bill_month` 倒序分页，未来账单会占据首页，
  /// 因此单独用 `start=次月 1 日` 拉一次，反转成本地升序后拼在列表末尾。
  final List<BillItem> _futureItems = <BillItem>[];

  final Map<int, String> _platforms = <int, String>{};
  BillStats? _stats;

  List<HousingItem>? _housings;
  List<UtilityItem>? _utilities;
  List<SubscriptionItem>? _subscriptions;

  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;

  /// 主列表（当前月及以前）的总条数，用于判断「加载更多」。
  int _mainTotal = 0;

  /// 主列表的查询上限（本月最后一天），加载更多时复用。
  String _mainEnd = '';
  bool _hasMore = true;
  bool _loadingMore = false;

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

  /// 按当前 Tab 拉取数据；首次切换时按需加载，之后切换只重绘。
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
      _status = LoadStatus.loading;
      _message = null;
    });
    try {
      switch (_tab) {
        case 0:
          await _loadLoan(scope);
        case 1:
          await _loadHousing(scope);
        case 2:
          await _loadSubscriptions(scope);
      }
      if (!mounted) {
        return;
      }
      setState(() => _status = LoadStatus.ready);
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

  /// 网贷借还：汇总 + 账单列表 + 平台名映射。
  ///
  /// 排序口径：月份顺序完全由后端决定（`bill_month` 倒序），客户端只按
  /// 数据顺序分组渲染，不跨页重排。为了把「未来月份」整体压到末尾，列表
  /// 拆成两块：主列表（`end` = 本月最后一天）先按后端分页取完，未来块
  /// （`start` = 次月 1 日）取完后整块反转成正序。两块都取完再渲染，
  /// 避免未来月份插到已加载的近期月份中间、或分页之间漏月份。
  Future<void> _loadLoan(AppScope scope) async {
    final DateTime now = DateTime.now();
    final String mainEnd = _dateKey(DateTime(now.year, now.month + 1, 0));
    final String futureStart = _dateKey(DateTime(now.year, now.month + 1, 1));
    final List<Map<String, dynamic>?> basics =
        await Future.wait(<Future<Map<String, dynamic>?>>[
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-bills/stats',
            queryParameters: <String, dynamic>{'days': 0},
          )
          .then((value) => value.data),
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-platforms',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data),
    ]);
    final Map<String, dynamic>? statsJson = basics[0];
    final Map<String, dynamic>? platformJson = basics[1];
    if (statsJson == null) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '账单接口返回数据为空',
      );
    }
    final List<({List<BillItem> items, int total})> both =
        await Future.wait(<Future<({List<BillItem> items, int total})>>[
      _fetchBills(scope, end: mainEnd),
      _fetchBills(scope, start: futureStart, reverse: true),
    ]);
    final ({List<BillItem> items, int total}) main = both[0];
    final ({List<BillItem> items, int total}) future = both[1];
    final Map<int, String> platforms = <int, String>{};
    for (final Map item
        in ((platformJson?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()) {
      platforms[(item['id'] as num?)?.toInt() ?? -1] =
          item['name'] as String? ?? '';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _stats = BillStats.fromJson(statsJson);
      _items
        ..clear()
        ..addAll(main.items);
      _futureItems
        ..clear()
        ..addAll(future.items);
      _platforms
        ..clear()
        ..addAll(platforms);
      _page = _pagesFor(main.total);
      _mainEnd = mainEnd;
      _mainTotal = main.total;
      _total = main.total + future.total;
      _hasMore = _items.length < _mainTotal;
    });
  }

  /// 列表每页条数。按 100 取，347 条只需 4 次请求。
  static const int _pageSize = 100;

  /// 取一页 100 条时，`total` 条记录需要翻多少页。
  int _pagesFor(int total) =>
      total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;

  /// 按后端 `bill_month` 倒序取完所有页（最多 10 页，防止异常数据死循环）。
  ///
  /// [end] / [start] 用于把列表切成「本月及以前」和「未来」两块。
  /// [reverse] 为 true 时整块反转（未来块用，得到未来月份正序）。
  Future<({List<BillItem> items, int total})> _fetchBills(
    AppScope scope, {
    String? end,
    String? start,
    bool reverse = false,
  }) async {
    final List<BillItem> items = <BillItem>[];
    int total = 0;
    for (int page = 1; page <= 10; page++) {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/loan-bills',
                  queryParameters: <String, dynamic>{
            'page': page,
            'page_size': _pageSize,
            'end': ?end,
            'start': ?start,
          }))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '账单接口返回数据为空',
        );
      }
      total = (json['total'] as num?)?.toInt() ?? items.length;
      final List<BillItem> batch = _parseBills(json);
      items.addAll(batch);
      if (batch.isEmpty || items.length >= total) {
        break;
      }
    }
    return (items: reverse ? items.reversed.toList() : items, total: total);
  }

  /// 房租水电：住房与水电记录各取前 100 条（与网页端列表口径一致）。
  Future<void> _loadHousing(AppScope scope) async {
    final List<Map<String, dynamic>?> responses =
        await Future.wait(<Future<Map<String, dynamic>?>>[
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/housing',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data),
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/utilities',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data),
    ]);
    final Map<String, dynamic>? housingJson = responses[0];
    final Map<String, dynamic>? utilityJson = responses[1];
    if (housingJson == null || utilityJson == null) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '房租水电接口返回数据为空',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _housings = _parseList(housingJson, HousingItem.fromJson);
      _utilities = _parseList(utilityJson, UtilityItem.fromJson);
    });
  }

  /// 服务订阅：取前 100 条。
  Future<void> _loadSubscriptions(AppScope scope) async {
    final Map<String, dynamic>? json = (await scope.apiClient
            .get<Map<String, dynamic>>('/finance/subscriptions',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100}))
        .data;
    if (json == null) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '订阅接口返回数据为空',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _subscriptions = _parseList(json, SubscriptionItem.fromJson);
    });
  }

  /// 加载更多（仅网贷借还使用，>1000 条时才出现）：沿用后端月份倒序追加更早月份。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/loan-bills',
                  queryParameters: <String, dynamic>{
            'page': _page + 1,
            'page_size': _pageSize,
            'end': _mainEnd,
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
        _items.addAll(_parseBills(json));
        _hasMore = _items.length < _mainTotal;
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

  List<BillItem> _parseBills(Map<String, dynamic> json) =>
      _parseList(json, BillItem.fromJson);

  /// 通用分页解析：`items` 逐项交给构造函数。
  List<T> _parseList<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) => fromJson(item.cast<String, dynamic>()))
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

  /// 切换 Tab：未加载过的数据先拉取，已加载的直接切换。
  void _selectTab(int index) {
    if (index == _tab) {
      return;
    }
    setState(() => _tab = index);
    final bool loaded = switch (index) {
      1 => _housings != null && _utilities != null,
      2 => _subscriptions != null,
      _ => _stats != null,
    };
    if (!loaded) {
      _refresh();
    }
  }

  /// 打开新增 / 编辑表单；保存或删除成功返回 true 时刷新当前 Tab。
  Future<void> _openForm(BillKind kind, {int? id}) async {
    final String path = id == null
        ? '/finance/bills/new'
        : '/finance/bills/edit/$id';
    final bool? changed = await context.push<bool>(
      '$path?kind=${kind.name}',
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 打开当前 Tab 的配套字典维护页（平台 / 渠道 / 分类）。
  Future<void> _openManage() async {
    final String kind = switch (_tab) {
      1 => 'housing',
      2 => 'subscription',
      _ => 'loan',
    };
    await context.push<Object?>('/finance/bills/manage/$kind');
    if (mounted) {
      await _refresh();
    }
  }

  /// 详情层：先看完整字段，再决定编辑或删除。
  ///
  /// 编辑交给 [BillKind] 对应的表单页（返回 true 时重拉当前 Tab）；
  /// 删除已在详情层内二次确认完成，这里只负责刷新列表。
  Future<void> _showBillDetail({
    required BillKind kind,
    required int id,
    required Widget Function(VoidCallback onMutated) sheetBuilder,
  }) async {
    // 详情层被返回键或下滑关闭时 pop 不带结果，用回调兜底记住「发生过变更」
    bool mutated = false;
    final BillDetailAction? action =
        await showModalBottomSheet<BillDetailAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => sheetBuilder(() => mutated = true),
    );
    if (!mounted) {
      return;
    }
    if (action == BillDetailAction.edit) {
      await _openForm(kind, id: id);
      return;
    }
    if (mutated || action != null) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String manageLabel = switch (_tab) {
      1 => '维护租房渠道',
      2 => '维护订阅分类',
      _ => '维护网贷平台',
    };
    return DetailPageScaffold(
      title: '账单管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          V2Segmented<int>(
            options: const <V2SegmentedOption<int>>[
              V2SegmentedOption<int>(label: '网贷借还', value: 0),
              V2SegmentedOption<int>(label: '房租水电', value: 1),
              V2SegmentedOption<int>(label: '服务订阅', value: 2),
            ],
            selected: _tab,
            onChanged: _selectTab,
          ),
          Expanded(child: _body(manageLabel)),
        ],
      ),
    );
  }

  /// 当前栏目内容：未就绪时只显示状态条，就绪后按 Tab 就地切换。
  Widget _body(String manageLabel) {
    final bool ready = _status == LoadStatus.ready || _status == LoadStatus.idle;
    if (!ready) {
      return ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
      );
    }
    return IndexedStack(
      index: _tab,
      children: <Widget>[
        _loanView(),
        _housingView(manageLabel),
        _subscriptionView(manageLabel),
      ],
    );
  }

  /// 网贷「全部账单」：摘要 + 即将到期 + 按月分组的懒加载账单列表。
  ///
  /// 排序口径：月份取 `bill_month`，当前月及以前按月份倒序（最近的在上），
  /// 未来月份统一排到末尾并在未来组内按时间正序；组内按到期日倒序、
  /// 同日按 id 倒序；平台仅作行内信息，不参与排序与分组。
  /// 月份分组头使用固定高度 sliver header，滚动时吸顶；「加载更多」按
  /// 服务端顺序（`bill_month` 倒序）追加更早的月份，不会打乱已加载的分组。
  Widget _loanView() {
    final AppTokens tokens = AppTokens.of(context);
    final BillStats? stats = _stats;
    if (stats == null) {
      return const SizedBox.shrink();
    }
    final List<({String month, List<BillItem> bills})> groups = _loanGroups();
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              SummaryStrip(
                caption: '待还 ${formatInt(stats.pendingCount)} 笔 · '
                    '部分还款 ${formatInt(stats.partialCount)} · '
                    '已结清 ${formatInt(stats.clearedCount)}',
                items: <StatRailItem>[
                  StatRailItem(
                    label: '待还',
                    value: formatInt(stats.remaining),
                    unit: '元',
                    color: tokens.red,
                  ),
                  StatRailItem(
                    label: '已还',
                    value: formatInt(stats.paid),
                    unit: '元',
                    color: tokens.green,
                  ),
                  StatRailItem(
                    label: '利息合计',
                    value: formatInt(stats.totalInterest),
                    unit: '元',
                  ),
                ],
              ),
              if (stats.upcoming.isNotEmpty) ...<Widget>[
                const SectionHeader(title: '即将到期'),
                GroupCard(
                  children: <Widget>[
                    for (final BillItem bill in stats.upcoming)
                      BillRow(
                        bill: bill,
                        platformName: _platformName(bill.platformId),
                        // 到期日已经在下行完整显示，行内再带账单月会挤掉平台名。
                        showMonth: false,
                        onTap: () => _openLoanDetail(bill),
                        onRepay:
                            bill.status == 'cleared' || bill.remaining <= 0
                                ? null
                                : () => _openRepay(bill),
                      ),
                  ],
                ),
              ],
              SectionHeader(
                title: '全部账单 · 共 ${formatInt(_total)} 笔',
                actionLabel: '新增账单',
                onAction: () => _openForm(BillKind.loan),
              ),
            ],
          ),
        ),
        if (_items.isEmpty && _futureItems.isEmpty)
          const SliverToBoxAdapter(
            child: GroupCard(
              children: <Widget>[
                EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: '还没有账单记录',
                  description: '点「新增账单」录入第一条',
                  compact: true,
                ),
              ],
            ),
          )
        else ...<Widget>[
          for (final ({String month, List<BillItem> bills}) group in groups)
            SliverMainAxisGroup(
              slivers: <Widget>[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _MonthHeaderDelegate(
                    label: group.month,
                    count: group.bills.length,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                        final BillItem bill = group.bills[index];
                        return BillRow(
                          bill: bill,
                          platformName: _platformName(bill.platformId),
                          showMonth: false,
                          onTap: () => _openLoanDetail(bill),
                          onRepay:
                              bill.status == 'cleared' || bill.remaining <= 0
                                  ? null
                                  : () => _openRepay(bill),
                        );
                      },
                      childCount: group.bills.length,
                    ),
                  ),
                ),
              ],
            ),
          SliverToBoxAdapter(
            child: ListLoadMoreFooter(
              loading: _loadingMore,
              hasMore: _hasMore,
              onPressed: _loadMore,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: GroupCard(
            children: <Widget>[
              V2EntryRow(
                title: '维护网贷平台',
                subtitle: '新增或整理网贷平台名称',
                icon: Icons.tune_outlined,
                onTap: _openManage,
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// 按 `bill_month` 分组。
  ///
  /// 顺序完全由数据来源决定：主列表按后端 `bill_month` 倒序分页追加，
  /// 客户端不跨页重排；未来块已整体反转为正序，拼在主列表之后。
  /// 组内只按到期日倒序、同日按 id 倒序（同组内排序，不会丢掉跨页记录）。
  List<({String month, List<BillItem> bills})> _loanGroups() {
    final Map<String, List<BillItem>> grouped = <String, List<BillItem>>{};
    for (final BillItem bill in <BillItem>[..._items, ..._futureItems]) {
      final String month = bill.billMonth.length >= 7
          ? bill.billMonth.substring(0, 7)
          : bill.billMonth;
      grouped.putIfAbsent(month, () => <BillItem>[]).add(bill);
    }
    for (final List<BillItem> bills in grouped.values) {
      bills.sort((BillItem a, BillItem b) {
        final String left = a.dueDate ?? '';
        final String right = b.dueDate ?? '';
        if (left != right) {
          return right.compareTo(left);
        }
        return b.id.compareTo(a.id);
      });
    }
    return <({String month, List<BillItem> bills})>[
      for (final String month in grouped.keys)
        (month: month, bills: grouped[month]!),
    ];
  }

  /// 当前月份的 `yyyy-MM` 键，用于区分「未来月份」。
  String _currentMonthKey() {
    final DateTime now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// 今天的 `yyyy-MM-dd`（用于按日期排序的 Tab：房租、订阅）。
  String _todayKey() => _dateKey(DateTime.now());

  /// `DateTime` → `yyyy-MM-dd`，作为列表接口 `start`/`end` 的取值。
  String _dateKey(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// 统一的「未来后置」排序：`today` 及以前按时间倒序（最近在前），
  /// 未来项整体排到末尾并按时间正序（先到期/先发生的在上）。
  int _compareFutureLast(String a, String b, String today) {
    final bool aFuture = a.compareTo(today) > 0;
    final bool bFuture = b.compareTo(today) > 0;
    if (aFuture != bFuture) {
      return aFuture ? 1 : -1;
    }
    return aFuture ? a.compareTo(b) : b.compareTo(a);
  }

  /// 房租水电：租房信息 + 水电缴费两个分组，附字典维护入口。
  Widget _housingView(String manageLabel) {
    final AppTokens tokens = AppTokens.of(context);
    // 与网贷 Tab 同一口径：当前及以前倒序在前，未来排到末尾且按时间正序。
    final String today = _todayKey();
    final List<HousingItem> housings = <HousingItem>[
      ...?_housings,
    ]..sort(
        (HousingItem a, HousingItem b) =>
            _compareFutureLast(a.moveInDate ?? '', b.moveInDate ?? '', today),
      );
    final List<UtilityItem> utilities = <UtilityItem>[
      ...?_utilities,
    ]..sort(
        (UtilityItem a, UtilityItem b) =>
            _compareFutureLast(a.billMonth, b.billMonth, _currentMonthKey()),
      );
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '租房信息 · ${formatInt(housings.length)} 条',
          actionLabel: '新增住房',
          onAction: () => _openForm(BillKind.housing),
        ),
        GroupCard(
          children: housings.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.home_outlined,
                    title: '暂无住房记录',
                    description: '点「新增住房」录入租房信息',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final HousingItem housing in housings)
                    _SimpleRow(
                      title: housing.name,
                      subtitle: '${housing.rentTermLabel} · 月租 '
                          '${formatMoney(housing.actualMonthlyRent)} · 入住 '
                          '${_shortDate(housing.moveInDate)}',
                      onTap: () => _openHousingDetail(housing),
                    ),
                ],
        ),
        SectionHeader(
          title: '水电缴费 · ${formatInt(utilities.length)} 条',
          actionLabel: '新增缴费',
          onAction: () => _openForm(BillKind.utility),
        ),
        GroupCard(
          children: utilities.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.water_drop_outlined,
                    title: '暂无水电记录',
                    description: '点「新增缴费」录入水费 / 电费',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final UtilityItem item in utilities)
                    _SimpleRow(
                      title: '${_shortMonth(item.billMonth)} · '
                          '${_feeTypeLabel(item.feeType)}',
                      subtitle: '${formatMoney(item.amount)}'
                          '${item.dueDate == null ? '' : ' · 到期 ${_shortDate(item.dueDate)}'}',
                      trailing: V2Badge(
                        item.paid ? '已缴' : '未缴',
                        tone: item.paid ? V2BadgeTone.green : V2BadgeTone.warn,
                      ),
                      onTap: () => _openUtilityDetail(item),
                    ),
                ],
        ),
        GroupCard(
          children: <Widget>[
            V2EntryRow(
              title: manageLabel,
              subtitle: '新增或整理房租 / 水电录入选项',
              icon: Icons.tune_outlined,
              onTap: _openManage,
            ),
          ],
        ),
        Text(
          '住房与水电记录与网页端共用同一份数据；删除前会再确认一次。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 服务订阅：订阅列表 + 字典维护入口。
  Widget _subscriptionView(String manageLabel) {
    final AppTokens tokens = AppTokens.of(context);
    final String today = _todayKey();
    final List<SubscriptionItem> items = <SubscriptionItem>[
      ...?_subscriptions,
    ]..sort(
        (SubscriptionItem a, SubscriptionItem b) => _compareFutureLast(
          a.startDate.length >= 10 ? a.startDate.substring(0, 10) : a.startDate,
          b.startDate.length >= 10 ? b.startDate.substring(0, 10) : b.startDate,
          today,
        ),
      );
    return ListPageBody(
      status: _status,
      message: _message,
      onRetry: _refresh,
      blocks: <Widget>[
        SectionHeader(
          title: '订阅列表 · ${formatInt(items.length)} 条',
          actionLabel: '新增订阅',
          onAction: () => _openForm(BillKind.subscription),
        ),
        GroupCard(
          children: items.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.subscriptions_outlined,
                    title: '暂无订阅',
                    description: '点「新增订阅」录入会员 / 服务器等周期性付费',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final SubscriptionItem item in items)
                    _SimpleRow(
                      title: item.planName == null || item.planName!.isEmpty
                          ? item.name
                          : '${item.name} · ${item.planName}',
                      subtitle: '${item.category} · '
                          '${formatMoney(item.amount)} / '
                          '${item.billingCycleLabel} · 开通 '
                          '${_shortDate(item.startDate)}',
                      trailing: V2Badge(
                        item.statusLabel,
                        tone: switch (item.status) {
                          'expired' => V2BadgeTone.gray,
                          'cancelled' => V2BadgeTone.gray,
                          _ => V2BadgeTone.green,
                        },
                      ),
                      onTap: () => _openSubscriptionDetail(item),
                    ),
                ],
        ),
        GroupCard(
          children: <Widget>[
            V2EntryRow(
              title: manageLabel,
              subtitle: '新增或整理订阅分类',
              icon: Icons.tune_outlined,
              onTap: _openManage,
            ),
          ],
        ),
        Text(
          '金额、周期与状态和网页端一致，修改后会同步更新。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 平台 id → 名称；未拉到平台列表时退化为「平台 id」。
  String _platformName(int id) {
    final String? name = _platforms[id];
    if (name == null || name.isEmpty) {
      return '平台 $id';
    }
    return name;
  }

  /// 列表行「还款」入口：打开底部弹层，成功后刷新汇总、列表与即将到期。
  Future<void> _openRepay(BillItem bill) async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => LoanRepaySheet(bill: bill),
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 网贷：详情层内可查看还款记录，再进入编辑/删除。
  void _openLoanDetail(BillItem bill) {
    _showBillDetail(
      kind: BillKind.loan,
      id: bill.id,
      sheetBuilder: (VoidCallback onMutated) => FinanceBillDetailSheet(
        kind: BillKind.loan,
        bill: bill,
        platformName: _platformName(bill.platformId),
        onMutated: onMutated,
      ),
    );
  }

  /// 住房：点列表项先弹出完整租房信息，详情层里再提供编辑。
  void _openHousingDetail(HousingItem item) {
    _showBillDetail(
      kind: BillKind.housing,
      id: item.id,
      sheetBuilder: (VoidCallback onMutated) => FinanceBillDetailSheet(
        kind: BillKind.housing,
        housing: item,
        onMutated: onMutated,
      ),
    );
  }

  /// 水电：详情层展示所属住房、账期、费用类型、到期与缴费状态。
  void _openUtilityDetail(UtilityItem item) {
    _showBillDetail(
      kind: BillKind.utility,
      id: item.id,
      sheetBuilder: (VoidCallback onMutated) => FinanceBillDetailSheet(
        kind: BillKind.utility,
        utility: item,
        housingName: _housingName(item.housingId),
        onMutated: onMutated,
      ),
    );
  }

  /// 订阅：详情层展示方案、周期、金额、起止与续费状态。
  void _openSubscriptionDetail(SubscriptionItem item) {
    _showBillDetail(
      kind: BillKind.subscription,
      id: item.id,
      sheetBuilder: (VoidCallback onMutated) => FinanceBillDetailSheet(
        kind: BillKind.subscription,
        subscription: item,
        onMutated: onMutated,
      ),
    );
  }

  /// 住房 id → 名称；未关联或列表没加载到时返回 null（详情里显示「—」）。
  String? _housingName(int? id) {
    if (id == null) {
      return null;
    }
    for (final HousingItem item in _housings ?? const <HousingItem>[]) {
      if (item.id == id) {
        return item.name;
      }
    }
    return null;
  }

  /// `yyyy-MM-dd` → `MM-dd`，列表里节省横向空间。
  static String _shortDate(String? value) {
    if (value == null || value.isEmpty) {
      return '未设置';
    }
    return value.length >= 10 ? value.substring(5) : value;
  }

  /// `yyyy-MM-dd` → `yyyy-MM`。
  static String _shortMonth(String? value) {
    if (value == null || value.isEmpty) {
      return '—';
    }
    return value.length >= 7 ? value.substring(0, 7) : value;
  }

  /// 水电费用类型文案。
  static String _feeTypeLabel(String value) {
    switch (value) {
      case 'water':
        return '水费';
      case 'gas':
        return '燃气费';
      case 'property':
        return '物业费';
      case 'broadband':
        return '宽带费';
      case 'other':
        return '其他';
      default:
        return '电费';
    }
  }
}

/// 通用记录行：标题 + 副信息 + 可选状态徽标。
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: tokens.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「全部账单」月份分组头：固定高度并吸顶，滚动时始终压在当前月份之上。
class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MonthHeaderDelegate({required this.label, required this.count});

  final String label;
  final int count;

  @override
  double get minExtent => 32;

  @override
  double get maxExtent => 32;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      height: 32,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        // 用页面底色遮住下方滚动内容，避免吸顶时文字与账单行重叠。
        color: tokens.background,
        border: Border(
          bottom: BorderSide(color: tokens.line, width: AppTokens.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(label, style: AppType.section.copyWith(color: tokens.text2)),
          const Spacer(),
          Text(
            '$count 笔',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeaderDelegate oldDelegate) {
    return oldDelegate.label != label || oldDelegate.count != count;
  }
}
