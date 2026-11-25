import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/models/report_models.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_status.dart';
import '../../shared/widgets/v2/domain_header.dart';
import '../../shared/widgets/v2/domain_tabs.dart';
import '../../shared/widgets/v2/hero_metric.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_icon_button.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_search.dart';
import '../../theme/app_tokens.dart';
import '../reports/report_list_page.dart';
import 'finance_bills_page.dart';
import 'finance_debts_page.dart';
import 'finance_planning_page.dart';
import 'finance_shopping_page.dart';
import 'finance_transactions_page.dart';
import 'finance_travel_page.dart';

/// 财务中心 2.0 首屏：本月支出 Hero + 待还/债务/贷款指标 + 待还账单 + 分类支出。
///
/// 数据全部来自 `GET /finance/overview`，不新增业务口径：
/// - 「待还」是本月网贷账单未还，「贷款」是网贷全量未还；
/// - 后端没有收入字段，因此 Hero 用「本月支出」而不是「本月结余」。
class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  static const List<_FinanceTab> _tabs = <_FinanceTab>[
    _FinanceTab(label: '概览'),
    _FinanceTab(label: '账单', route: '/finance/bills'),
    _FinanceTab(label: '债务', route: '/finance/debts'),
    _FinanceTab(label: '购物', route: '/finance/shopping'),
    _FinanceTab(label: '旅行', route: '/finance/travel'),
    _FinanceTab(label: '规划', route: '/finance/planning'),
    _FinanceTab(label: '流水', route: '/finance/transactions'),
    _FinanceTab(label: '报告', route: '/finance/reports'),
  ];

  int _activeTab = 0;

  /// 已打开过的栏目：首次点击才构建页面，之后由 [IndexedStack] 保活。
  final Set<int> _visitedTabs = <int>{0};

  /// 点击栏目：内容就地切换，不再压栈跳转；切回概览时刷新一次摘要。
  void _openTab(int index) {
    if (index == _activeTab) {
      return;
    }
    final bool backToOverview = index == 0;
    setState(() {
      _activeTab = index;
      _visitedTabs.add(index);
    });
    if (backToOverview) {
      unawaited(AppScope.of(context).overview.refreshFinance());
    }
  }

  /// 栏目序号 → 内容页。索引与 [_tabs] 一一对应。
  Widget _tabPage(int index) {
    switch (index) {
      case 1:
        return const FinanceBillsPage();
      case 2:
        return const FinanceDebtsPage();
      case 3:
        return const FinanceShoppingPage();
      case 4:
        return const FinanceTravelPage();
      case 5:
        return const FinancePlanningPage();
      case 6:
        return const FinanceTransactionsPage();
      case 7:
        return const ReportListPage(source: ReportSource.finance);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 财务功能搜索。
  Future<void> _openSearch() async {
    final String? route = await openV2Search(
      context,
      hint: '搜索财务功能',
      sections: const <V2SearchSection>[
        V2SearchSection(
          title: '财务功能',
          entries: <V2SearchEntry>[
            V2SearchEntry(
              title: '账单管理',
              subtitle: '网贷 · 房租 · 订阅 · 水电',
              icon: Icons.receipt_long_outlined,
              route: '/finance/bills',
              keywords: '账单 网贷 房租 订阅 水电 还款',
            ),
            V2SearchEntry(
              title: '债务往来',
              subtitle: '借入 · 借出 · 结清',
              icon: Icons.handshake_outlined,
              route: '/finance/debts',
              keywords: '债务 借款 还款 借出 借入',
            ),
            V2SearchEntry(
              title: '购物记录',
              subtitle: '消费明细与平台分类',
              icon: Icons.shopping_bag_outlined,
              route: '/finance/shopping',
              keywords: '购物 消费 买东西 平台',
            ),
            V2SearchEntry(
              title: '旅行开支',
              subtitle: '行程与旅行明细',
              icon: Icons.flight_takeoff_outlined,
              route: '/finance/travel',
              keywords: '旅行 出行 机票 酒店 开支',
            ),
            V2SearchEntry(
              title: '财务规划',
              subtitle: '储蓄目标与进度',
              icon: Icons.flag_outlined,
              route: '/finance/planning',
              keywords: '规划 目标 储蓄 预算',
            ),
            V2SearchEntry(
              title: '资金流水',
              subtitle: '全部收支记录',
              icon: Icons.swap_vert_outlined,
              route: '/finance/transactions',
              keywords: '流水 收支 记录',
            ),
            V2SearchEntry(
              title: '财务报告',
              subtitle: '周期汇总与 PDF 导出',
              icon: Icons.description_outlined,
              route: '/finance/reports',
              keywords: '报告 汇总 PDF 导出',
            ),
          ],
        ),
      ],
    );
    if (route != null && mounted) {
      // 搜索结果若是域内栏目，直接切到对应栏目，保持「不跳转」的一致体验。
      final int index = _tabs.indexWhere(
        (_FinanceTab tab) => tab.route == route,
      );
      if (index > 0) {
        _openTab(index);
      } else {
        await context.push(route);
        if (mounted) {
          await AppScope.of(context).overview.refreshFinance();
        }
      }
    }
  }

  /// 快速记账面板：复用现有三类高频表单，不重复实现字段与校验。
  Future<void> _openQuickRecord() async {
    final String? route = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (BuildContext context) => const _QuickFinanceSheet(),
    );
    if (route != null && mounted) {
      await context.push(route);
      if (mounted) {
        await AppScope.of(context).overview.refreshFinance();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: scope.overview.financeNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<FinanceOverview> state = scope.overview.finance;
        final FinanceOverview? data = state.data;
        final bool loading = data == null && state.status == LoadStatus.loading;

        return PopScope(
          // 根页始终不退出：栏目内按返回键先回到概览，再按一次留在概览。
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop && _activeTab != 0) {
              _openTab(0);
            }
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: isDark
                ? SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: Colors.transparent,
                  )
                : SystemUiOverlayStyle.dark.copyWith(
                    statusBarColor: Colors.transparent,
                  ),
            child: Scaffold(
              backgroundColor: tokens.background,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: <Widget>[
                    DomainHeader(
                      title: '财务',
                      actions: <Widget>[
                        V2IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: '搜索财务功能',
                          onPressed: _openSearch,
                        ),
                        const NotificationBell(compact: true),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.pagePadding,
                      ),
                      child: DomainTabs(
                        labels: _tabs
                            .map((_FinanceTab tab) => tab.label)
                            .toList(growable: false),
                        selectedIndex: _activeTab,
                        onSelected: _openTab,
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _activeTab,
                        children: <Widget>[
                          RefreshIndicator(
                            onRefresh: scope.overview.refreshFinance,
                            color: tokens.accent,
                            backgroundColor: tokens.surface,
                            child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppTokens.pagePadding,
                            6,
                            AppTokens.pagePadding,
                            112,
                          ),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            if (state.status != LoadStatus.idle &&
                                state.status != LoadStatus.ready) ...<Widget>[
                              OverviewStatusBanner(
                                status: state.status,
                                message: state.message,
                                onRetry: scope.overview.retry,
                              ),
                              const SizedBox(height: 12),
                            ],
                            HeroMetric(
                              label: '本月支出',
                              value: loading
                                  ? '…'
                                  : formatMoney(data?.monthExpense),
                              subtitle: _heroSubtitle(data, state.status),
                            ),
                            const SizedBox(height: 14),
                            StatRail(
                              items: <StatRailItem>[
                                StatRailItem(
                                  label: '待还',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.unpaidBills),
                                  unit: loading ? null : '元',
                                ),
                                StatRailItem(
                                  label: '债务',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.outstandingDebt),
                                  unit: loading ? null : '元',
                                ),
                                StatRailItem(
                                  label: '贷款',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.outstandingLoans),
                                  unit: loading ? null : '元',
                                ),
                              ],
                            ),
                            SectionHeader(
                              title: '待还账单',
                              actionLabel: '全部',
                              onAction: () => _openTab(1),
                            ),
                            _pendingGroup(context, data, state.status),
                            SectionHeader(
                              title: '本月支出构成',
                              actionLabel: '报告',
                              onAction: () => _openTab(7),
                            ),
                            _categoryGroup(context, data, state.status),
                          ],
                        ),
                          ),
                          for (int i = 1; i < _tabs.length; i++)
                            if (_visitedTabs.contains(i))
                              DetailPageEmbedded(child: _tabPage(i))
                            else
                              const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButton: _activeTab == 0
                  ? FloatingActionButton(
                      tooltip: '快速记账',
                      onPressed: _openQuickRecord,
                      shape: const CircleBorder(),
                      child: const Icon(Icons.add),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }

  String _heroSubtitle(FinanceOverview? data, LoadStatus status) {
    if (data == null) {
      return status == LoadStatus.loading ? '正在加载财务数据…' : '暂无数据，下拉刷新重试';
    }
    return '待还 ${formatMoney(data.unpaidBills)} · 贷款余额 ${formatMoney(data.outstandingLoans)}';
  }

  /// 待还账单：最多 3 条，剩余天数在副信息里表达，金额用支出红。
  Widget _pendingGroup(
    BuildContext context,
    FinanceOverview? data,
    LoadStatus status,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final List<PendingBill> bills = data?.pendingBills ?? const <PendingBill>[];
    if (bills.isEmpty) {
      return _EmptyCard(
        title: data == null
            ? (status == LoadStatus.loading ? '正在加载待还账单…' : '暂无待还账单数据')
            : '暂无待还账单',
        subtitle: data == null ? '下拉刷新或点击重试' : '本月账单已结清',
      );
    }
    return GroupCard(
      children: <Widget>[
        for (final PendingBill bill in bills.take(3))
          RecordRow(
            title: _billTitle(bill.title),
            subtitle: _dueSubtitle(bill.dueDate),
            value: formatMoney(bill.remaining),
            valueColor: tokens.red,
            onTap: () => _openTab(1),
          ),
      ],
    );
  }

  /// 分类支出：后端已按金额倒序，取前三类，完整报告去报告页。
  Widget _categoryGroup(
    BuildContext context,
    FinanceOverview? data,
    LoadStatus status,
  ) {
    final List<FinanceCategory> categories =
        data?.categories ?? const <FinanceCategory>[];
    if (categories.isEmpty) {
      return _EmptyCard(
        title: data == null
            ? (status == LoadStatus.loading ? '正在加载分类支出…' : '暂无分类支出数据')
            : '本月还没有分类支出',
        subtitle: data == null ? '下拉刷新或点击重试' : '记录一笔支出后自动汇总',
      );
    }
    return GroupCard(
      children: <Widget>[
        for (final FinanceCategory category in categories.take(3))
          RecordRow(
            title: category.label,
            value: formatMoney(category.amount),
            onTap: () => _openTab(7),
          ),
      ],
    );
  }

  /// 去掉后端拼在账单标题里的日期，日期单独放在副信息。
  static String _billTitle(String raw) {
    final String title = raw.replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}$'), '');
    return title.isEmpty ? '账单' : title;
  }

  static String _dueSubtitle(String? dueDate) {
    final String date = formatListDate(dueDate);
    final int? days = _daysLeft(dueDate);
    if (days == null) {
      return date;
    }
    if (days < 0) {
      return '$date · 已逾期 ${-days} 天';
    }
    if (days == 0) {
      return '$date · 今天到期';
    }
    return '$date · 剩 $days 天';
  }

  static int? _daysLeft(String? raw) {
    final String text = (raw ?? '').trim();
    if (text.length < 10) {
      return null;
    }
    final DateTime? due = DateTime.tryParse(text.substring(0, 10));
    if (due == null) {
      return null;
    }
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return due.difference(today).inDays;
  }
}

/// 财务域栏目的静态定义。
class _FinanceTab {
  const _FinanceTab({required this.label, this.route});

  final String label;
  final String? route;
}

/// 空态卡片：与 GroupCard 同底色，避免空白区域没有承接。
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return GroupCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: AppType.rowTitle.copyWith(color: tokens.text)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppType.rowMeta.copyWith(color: tokens.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 快速记账面板：账单 / 购物 / 旅行三类高频录入。
class _QuickFinanceSheet extends StatelessWidget {
  const _QuickFinanceSheet();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Material(
      color: tokens.surface,
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.fill,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '快速记账',
                style: AppType.rowTitle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 6),
              const _QuickFinanceRow(
                icon: Icons.receipt_long_outlined,
                title: '新增账单',
                subtitle: '网贷 · 房租 · 订阅 · 水电',
                route: '/finance/bills/new',
              ),
              const _QuickFinanceRow(
                icon: Icons.shopping_bag_outlined,
                title: '购物记录',
                subtitle: '商品 · 金额 · 平台 · 分类',
                route: '/finance/shopping/new',
              ),
              const _QuickFinanceRow(
                icon: Icons.flight_takeoff_outlined,
                title: '旅行开支',
                subtitle: '行程 · 交通 · 住宿明细',
                route: '/finance/travel/new',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickFinanceRow extends StatelessWidget {
  const _QuickFinanceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).pop(route),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.fill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: tokens.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
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
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 16, color: tokens.text3),
          ],
        ),
      ),
    );
  }
}
