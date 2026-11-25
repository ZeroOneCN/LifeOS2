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
import 'lifestyle_cards_page.dart';
import 'lifestyle_items_page.dart';

/// 生活中心 2.0 首屏：30 天内到期 Hero + 物品/卡片/扣费指标 + 到期时间线。
///
/// 数据来自 `GET /lifestyle/overview`；只展示已到期或 30 天内到期的物品，
/// 不做额外预测，避免把「可能过期」当成「已过期」。
class LifePage extends StatefulWidget {
  const LifePage({super.key});

  @override
  State<LifePage> createState() => _LifePageState();
}

class _LifePageState extends State<LifePage> {
  static const List<_LifeTab> _tabs = <_LifeTab>[
    _LifeTab(label: '概览'),
    _LifeTab(label: '物品', route: '/life/items'),
    _LifeTab(label: '卡片', route: '/life/cards'),
    _LifeTab(label: '报告', route: '/life/reports'),
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
      unawaited(AppScope.of(context).overview.refreshLifestyle());
    }
  }

  /// 栏目序号 → 内容页。索引与 [_tabs] 一一对应。
  Widget _tabPage(int index) {
    switch (index) {
      case 1:
        return const LifestyleItemsPage();
      case 2:
        return const LifestyleCardsPage();
      case 3:
        return const ReportListPage(source: ReportSource.lifestyle);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _openSearch() async {
    final String? route = await openV2Search(
      context,
      hint: '搜索生活功能',
      sections: const <V2SearchSection>[
        V2SearchSection(
          title: '生活功能',
          entries: <V2SearchEntry>[
            V2SearchEntry(
              title: '物品管理',
              subtitle: '有效期 · 日均成本 · 在用状态',
              icon: Icons.inventory_2_outlined,
              route: '/life/items',
              keywords: '物品 库存 有效期 过期 日均成本',
            ),
            V2SearchEntry(
              title: '卡片管理',
              subtitle: '手机卡 · 银行卡 · 账单扣费',
              icon: Icons.credit_card_outlined,
              route: '/life/cards',
              keywords: '卡片 手机卡 银行卡 账单 扣费',
            ),
            V2SearchEntry(
              title: '生活报告',
              subtitle: '周期汇总与 PDF 导出',
              icon: Icons.description_outlined,
              route: '/life/reports',
              keywords: '报告 汇总 PDF 导出',
            ),
          ],
        ),
      ],
    );
    if (route != null && mounted) {
      // 搜索结果若是域内栏目，直接切到对应栏目，保持「不跳转」的一致体验。
      final int index = _tabs.indexWhere((_LifeTab tab) => tab.route == route);
      if (index > 0) {
        _openTab(index);
      } else {
        await context.push(route);
        if (mounted) {
          await AppScope.of(context).overview.refreshLifestyle();
        }
      }
    }
  }

  Future<void> _openQuickRecord() async {
    final String? route = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (BuildContext context) => const _QuickLifeSheet(),
    );
    if (route != null && mounted) {
      await context.push(route);
      if (mounted) {
        await AppScope.of(context).overview.refreshLifestyle();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: scope.overview.lifestyleNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<LifestyleOverview> state = scope.overview.lifestyle;
        final LifestyleOverview? data = state.data;
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
                      title: '生活',
                      actions: <Widget>[
                        V2IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: '搜索生活功能',
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
                            .map((_LifeTab tab) => tab.label)
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
                            onRefresh: scope.overview.refreshLifestyle,
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
                            // 首次加载由 Hero 的「…」与副标题表达，不再叠加状态条；
                            // 只有失败 / 未登录 / 连接失败才需要显性提示与重试。
                            if (state.status != LoadStatus.idle &&
                                state.status != LoadStatus.ready &&
                                state.status != LoadStatus.loading) ...<Widget>[
                              OverviewStatusBanner(
                                status: state.status,
                                message: state.message,
                                onRetry: scope.overview.retry,
                              ),
                              const SizedBox(height: 12),
                            ],
                            HeroMetric(
                              label: '30 天内到期',
                              value: loading
                                  ? '…'
                                  : formatInt(data?.itemExpiring),
                              unit: loading ? null : '项',
                              subtitle: _heroSubtitle(data, state.status),
                            ),
                            const SizedBox(height: 14),
                            StatRail(
                              items: <StatRailItem>[
                                StatRailItem(
                                  label: '物品',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.itemTotal),
                                  unit: loading ? null : '件',
                                ),
                                StatRailItem(
                                  label: '卡片',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.cardTotal),
                                  unit: loading ? null : '张',
                                ),
                                StatRailItem(
                                  label: '本月扣费',
                                  value: loading
                                      ? '…'
                                      : formatInt(data?.monthDeduct),
                                  unit: loading ? null : '元',
                                ),
                              ],
                            ),
                            SectionHeader(
                              title: '到期时间线',
                              actionLabel: '全部',
                              onAction: () => _openTab(1),
                            ),
                            _expiringGroup(context, data, state.status),
                            const SectionHeader(title: '更多'),
                            GroupCard(
                              children: <Widget>[
                                V2EntryRow(
                                  title: '生活报告',
                                  subtitle: '周期汇总与 PDF 导出',
                                  icon: Icons.description_outlined,
                                  onTap: () => _openTab(3),
                                ),
                              ],
                            ),
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
                      tooltip: '快速新增',
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

  String _heroSubtitle(LifestyleOverview? data, LoadStatus status) {
    if (data == null) {
      return status == LoadStatus.loading ? '正在加载生活数据…' : '暂无数据，下拉刷新重试';
    }
    final List<ExpiringItem> items = data.expiringItems;
    if (items.isEmpty) {
      return '30 天内没有到期物品';
    }
    final ExpiringItem nearest = items.reduce(
      (ExpiringItem a, ExpiringItem b) =>
          (a.daysLeft ?? 1 << 30) <= (b.daysLeft ?? 1 << 30) ? a : b,
    );
    final int? days = nearest.daysLeft;
    return days == null
        ? '有 ${items.length} 项需要关注'
        : '最近 $days 天 · ${nearest.name}';
  }

  Widget _expiringGroup(
    BuildContext context,
    LifestyleOverview? data,
    LoadStatus status,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final List<ExpiringItem> items =
        data?.expiringItems ?? const <ExpiringItem>[];
    if (items.isEmpty) {
      return GroupCard(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data == null
                      ? (status == LoadStatus.loading ? '正在加载到期物品…' : '暂无到期数据')
                      : '30 天内没有到期物品',
                  style: AppType.rowTitle.copyWith(color: tokens.text),
                ),
                const SizedBox(height: 2),
                Text(
                  data == null ? '下拉刷新或点击重试' : '物品和卡片都在有效期内',
                  style: AppType.rowMeta.copyWith(color: tokens.text2),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return GroupCard(
      children: <Widget>[
        for (final ExpiringItem item in items.take(4))
          TaskRow(
            title: item.name,
            subtitle: _itemSubtitle(item),
            trailing: V2Badge(
              _daysLabel(item.daysLeft),
              tone: _daysTone(item.daysLeft),
            ),
            onTap: () => _openTab(1),
          ),
      ],
    );
  }

  static String _itemSubtitle(ExpiringItem item) {
    final List<String> parts = <String>[
      if ((item.expireDate ?? '').isNotEmpty) formatListDate(item.expireDate),
      if ((item.category ?? '').trim().isNotEmpty) item.category!.trim(),
    ];
    return parts.isEmpty ? '即将到期' : parts.join(' · ');
  }

  static String _daysLabel(int? days) {
    if (days == null) {
      return '待确认';
    }
    if (days < 0) {
      return '已过期 ${-days} 天';
    }
    if (days == 0) {
      return '今天到期';
    }
    return '剩 $days 天';
  }

  static V2BadgeTone _daysTone(int? days) {
    if (days == null) {
      return V2BadgeTone.gray;
    }
    if (days < 0) {
      return V2BadgeTone.danger;
    }
    if (days <= 7) {
      return V2BadgeTone.warn;
    }
    return V2BadgeTone.gray;
  }
}

/// 生活域栏目的静态定义。
class _LifeTab {
  const _LifeTab({required this.label, this.route});

  final String label;
  final String? route;
}

/// 快速新增面板：物品 / 银行卡 / 手机卡。
class _QuickLifeSheet extends StatelessWidget {
  const _QuickLifeSheet();

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
                '快速新增',
                style: AppType.rowTitle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 6),
              const _QuickLifeRow(
                icon: Icons.inventory_2_outlined,
                title: '新增物品',
                subtitle: '记录有效期与购买价格',
                route: '/life/items/new',
              ),
              const _QuickLifeRow(
                icon: Icons.credit_card_outlined,
                title: '新增银行卡',
                subtitle: '额度 · 账单日 · 有效期',
                route: '/life/cards/form/bank',
              ),
              const _QuickLifeRow(
                icon: Icons.smartphone_outlined,
                title: '新增手机卡',
                subtitle: '运营商 · 月租 · 余额',
                route: '/life/cards/form/phone',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickLifeRow extends StatelessWidget {
  const _QuickLifeRow({
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
