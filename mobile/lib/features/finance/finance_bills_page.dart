import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_tab_selector.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
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
  final Map<int, String> _platforms = <int, String>{};
  BillStats? _stats;

  List<HousingItem>? _housings;
  List<UtilityItem>? _utilities;
  List<SubscriptionItem>? _subscriptions;

  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
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

  /// 网贷借还：汇总 + 每页 20 条账单 + 平台名映射。
  Future<void> _loadLoan(AppScope scope) async {
    final List<Map<String, dynamic>?> responses =
        await Future.wait(<Future<Map<String, dynamic>?>>[
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-bills/stats',
            queryParameters: <String, dynamic>{'days': 0},
          )
          .then((value) => value.data),
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-bills',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
          )
          .then((value) => value.data),
      scope.apiClient
          .get<Map<String, dynamic>>(
            '/finance/loan-platforms',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )
          .then((value) => value.data),
    ]);
    final Map<String, dynamic>? statsJson = responses[0];
    final Map<String, dynamic>? listJson = responses[1];
    final Map<String, dynamic>? platformJson = responses[2];
    if (statsJson == null || listJson == null) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: '账单接口返回数据为空',
      );
    }
    final List<BillItem> items = _parseBills(listJson);
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
        ..addAll(items);
      _platforms
        ..clear()
        ..addAll(platforms);
      _page = 1;
      _total = (listJson['total'] as num?)?.toInt() ?? items.length;
      _hasMore = _items.length < _total;
    });
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

  /// 加载更多（仅网贷借还使用）。
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
        _items.addAll(_parseBills(json));
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

  /// 详情层：先看完整字段，再决定编辑或删除。
  ///
  /// 编辑交给 [BillKind] 对应的表单页（返回 true 时重拉当前 Tab）；
  /// 删除已在详情层内二次确认完成，这里只负责刷新列表。
  Future<void> _showBillDetail({
    required BillKind kind,
    required int id,
    required Widget sheet,
  }) async {
    final BillDetailAction? action =
        await showModalBottomSheet<BillDetailAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => sheet,
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == BillDetailAction.edit) {
      await _openForm(kind, id: id);
    } else {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '账单管理',
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                AppTabSelector(
                  labels: const <String>['网贷借还', '房租水电', '服务订阅'],
                  value: _tab,
                  onChanged: _selectTab,
                ),
                ListStatusView(
                  status: _status,
                  message: _message,
                  onRetry: _refresh,
                ),
              ],
            ),
          ),
          if (_status == LoadStatus.ready)
            ...(_tab == 0
                ? _loanSlivers(theme)
                : <Widget>[
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: _content(theme),
                      ),
                    ),
                  ]),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
      ),
    );
  }

  /// 网贷「全部账单」按月分组的 sliver 列表。
  ///
  /// 排序口径与网页端一致：月份取 `bill_month`，按月份倒序；组内按到期日
  /// 倒序、同日按 id 倒序；平台仅作行内信息，不参与排序与分组。
  /// 月份分组头使用固定高度 sliver header，滚动时吸顶，「加载更多」只会
  /// 追加更早的月份，不会打乱已有分组。
  List<Widget> _loanSlivers(ThemeData theme) {
    final BillStats? stats = _stats;
    if (stats == null) {
      return const <Widget>[];
    }
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final List<({String month, List<BillItem> bills})> groups = _loanGroups();
    return <Widget>[
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: <Widget>[
            SectionCard(
              title: '合计',
              trailing: AppPrimaryAction(
                label: '新增账单',
                onPressed: () => _openForm(BillKind.loan),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: <Widget>[
                  Row(
                    spacing: 16,
                    children: <Widget>[
                      Expanded(
                        child: MetricPlaceholder(
                          label: '待还',
                          value: formatMoney(stats.remaining),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '已还',
                          value: formatMoney(stats.paid),
                        ),
                      ),
                      Expanded(
                        child: MetricPlaceholder(
                          label: '利息合计',
                          value: formatMoney(stats.totalInterest),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      StatusChip(
                        label: '待还 ${stats.pendingCount}',
                        tone: StatusTone.danger,
                      ),
                      StatusChip(
                        label: '部分还款 ${stats.partialCount}',
                        tone: StatusTone.warning,
                      ),
                      StatusChip(
                        label: '已结清 ${stats.clearedCount}',
                        tone: StatusTone.success,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (stats.upcoming.isNotEmpty)
              SectionCard(
                title: '即将到期',
                child: Column(
                  spacing: 4,
                  children: <Widget>[
                    for (final BillItem bill in stats.upcoming)
                      BillRow(
                        bill: bill,
                        platformName: _platformName(bill.platformId),
                        onTap: () => _openLoanDetail(bill),
                        onRepay:
                            bill.status == 'cleared' || bill.remaining <= 0
                                ? null
                                : () => _openRepay(bill),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  Text('全部账单', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '共 $_total 条',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (_items.isEmpty)
        const SliverToBoxAdapter(
          child: SectionCard(
            title: '暂无账单',
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '还没有账单记录',
              description: '点「新增账单」录入第一条',
              compact: true,
            ),
          ),
        )
      else ...<Widget>[
        for (final ({String month, List<BillItem> bills}) group
            in groups) ...<Widget>[
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
                    onRepay: bill.status == 'cleared' || bill.remaining <= 0
                        ? null
                        : () => _openRepay(bill),
                  );
                },
                childCount: group.bills.length,
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: _LoadMoreFooter(
            loading: _loadingMore,
            hasMore: _hasMore,
            onPressed: _loadMore,
          ),
        ),
      ],
    ];
  }

  /// 按 `bill_month` 分组并按月份倒序；组内按到期日倒序、同日按 id 倒序。
  List<({String month, List<BillItem> bills})> _loanGroups() {
    final Map<String, List<BillItem>> grouped = <String, List<BillItem>>{};
    for (final BillItem bill in _items) {
      final String month = bill.billMonth.length >= 7
          ? bill.billMonth.substring(0, 7)
          : bill.billMonth;
      grouped.putIfAbsent(month, () => <BillItem>[]).add(bill);
    }
    final List<String> months = grouped.keys.toList()
      ..sort((String a, String b) => b.compareTo(a));
    for (final String month in months) {
      grouped[month]!.sort((BillItem a, BillItem b) {
        final String left = a.dueDate ?? '';
        final String right = b.dueDate ?? '';
        if (left != right) {
          return right.compareTo(left);
        }
        return b.id.compareTo(a.id);
      });
    }
    return <({String month, List<BillItem> bills})>[
      for (final String month in months)
        (month: month, bills: grouped[month]!),
    ];
  }

  /// 当前 Tab 的内容区块。
  List<Widget> _content(ThemeData theme) {
    switch (_tab) {
      case 1:
        return _housingContent(theme);
      case 2:
        return _subscriptionContent(theme);
      default:
        return _loanContent(theme);
    }
  }

  List<Widget> _loanContent(ThemeData theme) {
    final BillStats? stats = _stats;
    if (stats == null) {
      return const <Widget>[];
    }
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return <Widget>[
      SectionCard(
        title: '合计',
        trailing: AppPrimaryAction(
          label: '新增账单',
          onPressed: () => _openForm(BillKind.loan),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: <Widget>[
            Row(
              spacing: 16,
              children: <Widget>[
                Expanded(
                  child: MetricPlaceholder(
                    label: '待还',
                    value: formatMoney(stats.remaining),
                  ),
                ),
                Expanded(
                  child: MetricPlaceholder(
                    label: '已还',
                    value: formatMoney(stats.paid),
                  ),
                ),
                Expanded(
                  child: MetricPlaceholder(
                    label: '利息合计',
                    value: formatMoney(stats.totalInterest),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                StatusChip(
                  label: '待还 ${stats.pendingCount}',
                  tone: StatusTone.danger,
                ),
                StatusChip(
                  label: '部分还款 ${stats.partialCount}',
                  tone: StatusTone.warning,
                ),
                StatusChip(
                  label: '已结清 ${stats.clearedCount}',
                  tone: StatusTone.success,
                ),
              ],
            ),
          ],
        ),
      ),
      if (stats.upcoming.isNotEmpty)
        SectionCard(
          title: '即将到期',
          child: Column(
            spacing: 4,
            children: <Widget>[
              for (final BillItem bill in stats.upcoming)
                BillRow(
                  bill: bill,
                  platformName: _platformName(bill.platformId),
                  onTap: () => _openLoanDetail(bill),
                  onRepay: bill.status == 'cleared' || bill.remaining <= 0
                      ? null
                      : () => _openRepay(bill),
                ),
            ],
          ),
        ),
      SectionCard(
        title: '全部账单',
        trailing: Text(
          '共 $_total 条',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        child: _items.isEmpty
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: '暂无账单',
                description: '点右上「新增账单」录入第一条',
                compact: true,
              )
            : Column(
                spacing: 4,
                children: <Widget>[
                  for (final BillItem bill in _items)
                    BillRow(
                      bill: bill,
                      platformName: _platformName(bill.platformId),
                      onTap: () => _openLoanDetail(bill),
                      onRepay: bill.status == 'cleared' || bill.remaining <= 0
                          ? null
                          : () => _openRepay(bill),
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
    ];
  }

  List<Widget> _housingContent(ThemeData theme) {
    // 与网页端一致：住房按入住日期倒序，水电按账单月份倒序。
    final List<HousingItem> housings = <HousingItem>[
      ...?_housings,
    ]..sort(
        (HousingItem a, HousingItem b) =>
            (b.moveInDate ?? '').compareTo(a.moveInDate ?? ''),
      );
    final List<UtilityItem> utilities = <UtilityItem>[
      ...?_utilities,
    ]..sort(
        (UtilityItem a, UtilityItem b) => b.billMonth.compareTo(a.billMonth),
      );
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return <Widget>[
      SectionCard(
        title: '租房信息',
        trailing: AppPrimaryAction(
          label: '新增住房',
          onPressed: () => _openForm(BillKind.housing),
        ),
        child: housings.isEmpty
            ? const EmptyState(
                icon: Icons.home_outlined,
                title: '暂无住房记录',
                description: '点右上「新增住房」录入租房信息',
                compact: true,
              )
            : Column(
                spacing: 4,
                children: <Widget>[
                  for (final HousingItem housing in housings)
                    _RecordRow(
                      title: housing.name,
                      subtitle: '${housing.rentTermLabel} · 月租 '
                          '${formatMoney(housing.actualMonthlyRent)} · 入住 '
                          '${_shortDate(housing.moveInDate)}',
                      onTap: () => _openHousingDetail(housing),
                    ),
                ],
              ),
      ),
      SectionCard(
        title: '水电缴费',
        trailing: AppPrimaryAction(
          label: '新增缴费',
          onPressed: () => _openForm(BillKind.utility),
        ),
        child: utilities.isEmpty
            ? const EmptyState(
                icon: Icons.water_drop_outlined,
                title: '暂无水电记录',
                description: '点右上「新增缴费」录入水费/电费',
                compact: true,
              )
            : Column(
                spacing: 4,
                children: <Widget>[
                  for (final UtilityItem item in utilities)
                    _RecordRow(
                      title: '${_shortMonth(item.billMonth)} · '
                          '${_feeTypeLabel(item.feeType)}',
                      subtitle: '${formatMoney(item.amount)}'
                          '${item.dueDate == null ? '' : ' · 到期 ${_shortDate(item.dueDate)}'}'
                          ' · ${item.paid ? '已缴' : '未缴'}',
                      trailing: StatusChip(
                        label: item.paid ? '已缴' : '未缴',
                        tone: item.paid ? StatusTone.success : StatusTone.warning,
                      ),
                      onTap: () => _openUtilityDetail(item),
                    ),
                ],
              ),
      ),
      Text(
        '住房与水电记录直接读写网页端同一批接口；删除前会二次确认。',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
    ];
  }

  List<Widget> _subscriptionContent(ThemeData theme) {
    final List<SubscriptionItem> items =
        _subscriptions ?? const <SubscriptionItem>[];
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return <Widget>[
      SectionCard(
        title: '订阅列表',
        trailing: AppPrimaryAction(
          label: '新增订阅',
          onPressed: () => _openForm(BillKind.subscription),
        ),
        child: items.isEmpty
            ? const EmptyState(
                icon: Icons.subscriptions_outlined,
                title: '暂无订阅',
                description: '点右上「新增订阅」录入会员/服务器等周期性付费',
                compact: true,
              )
            : Column(
                spacing: 4,
                children: <Widget>[
                  for (final SubscriptionItem item in items)
                    _RecordRow(
                      title: item.planName == null || item.planName!.isEmpty
                          ? item.name
                          : '${item.name} · ${item.planName}',
                      subtitle: '${item.category} · '
                          '${formatMoney(item.amount)} / '
                          '${item.billingCycleLabel} · 开通 '
                          '${_shortDate(item.startDate)}',
                      trailing: StatusChip(
                        label: item.statusLabel,
                        tone: switch (item.status) {
                          'expired' => StatusTone.info,
                          'cancelled' => StatusTone.info,
                          _ => StatusTone.success,
                        },
                      ),
                      onTap: () => _openSubscriptionDetail(item),
                    ),
                ],
              ),
      ),
      Text(
        '金额与周期、状态字段与网页端一致；修改会立即同步到网页端。',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
    ];
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
      sheet: FinanceBillDetailSheet(
        kind: BillKind.loan,
        bill: bill,
        platformName: _platformName(bill.platformId),
      ),
    );
  }

  /// 住房：点列表项先弹出完整租房信息，详情层里再提供编辑。
  void _openHousingDetail(HousingItem item) {
    _showBillDetail(
      kind: BillKind.housing,
      id: item.id,
      sheet: FinanceBillDetailSheet(
        kind: BillKind.housing,
        housing: item,
      ),
    );
  }

  /// 水电：详情层展示所属住房、账期、费用类型、到期与缴费状态。
  void _openUtilityDetail(UtilityItem item) {
    _showBillDetail(
      kind: BillKind.utility,
      id: item.id,
      sheet: FinanceBillDetailSheet(
        kind: BillKind.utility,
        utility: item,
        housingName: _housingName(item.housingId),
      ),
    );
  }

  /// 订阅：详情层展示方案、周期、金额、起止与续费状态。
  void _openSubscriptionDetail(SubscriptionItem item) {
    _showBillDetail(
      kind: BillKind.subscription,
      id: item.id,
      sheet: FinanceBillDetailSheet(
        kind: BillKind.subscription,
        subscription: item,
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

/// 通用记录行：标题 + 副标题 + 可选状态芯片。
class _RecordRow extends StatelessWidget {
  const _RecordRow({
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
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          spacing: 8,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

/// 「加载更多 / 已全部加载」页脚。
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

/// 「全部账单」月份分组头：固定高度并吸顶，滚动时始终压在当前月份之上。
class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MonthHeaderDelegate({required this.label, required this.count});

  final String label;
  final int count;

  @override
  double get minExtent => 34;

  @override
  double get maxExtent => 34;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(label, style: theme.textTheme.titleSmall),
          const Spacer(),
          Text(
            '$count 笔',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
