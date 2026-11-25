import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/data/overview_models.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../shared/widgets/section_status.dart';
import '../../shared/widgets/v2/domain_header.dart';
import '../../shared/widgets/v2/domain_tabs.dart';
import '../../shared/widgets/v2/hero_metric.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_icon_button.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_search.dart';
import '../../theme/app_tokens.dart';

/// 健康中心 2.0 首屏：大标题 + 6 等分栏目 + Hero 步数 + 指标轨 + 今日用药 + 最近记录。
///
/// 与旧版「常用 2×2 + 全部功能网格」相比，首屏先回答「今天状态如何」，
/// 功能入口收敛为一行栏目；刷新只保留下拉刷新。
///
/// 摘要数据来自 `GET /health/overview`；
/// 7 日均步数单独取 `GET /health/steps/stats?days=7`：
/// 总览里的 `week_summary.steps_avg` 是按「记录条数」平均，
/// 一天有多条分时段记录时会被拉低（实测 1,385 vs 真实日均 4,100），
/// 因此不能直接当「日均」展示。
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  OverviewController? _overview;

  /// 近 7 日日均步数（按天取最大值后平均，口径与步数统计页一致）。
  int? _weekAvgSteps;
  bool _weekStatsLoading = false;
  bool _weekStatsFailed = false;

  /// 当前高亮的栏目。概览固定为 0；点击其它栏目先高亮再跳转，返回后归位。
  int _activeTab = 0;

  /// 域内栏目：统一 2 个汉字，顺序与效果稿一致。
  static const List<_HealthTab> _tabs = <_HealthTab>[
    _HealthTab(label: '概览'),
    _HealthTab(label: '睡眠', route: '/health/vitals-sleep'),
    _HealthTab(label: '用药', route: '/health/medication'),
    _HealthTab(label: '运动', route: '/health/fitness'),
    _HealthTab(label: '饮食', route: '/health/diet'),
    _HealthTab(label: '体重', route: '/health/body'),
    _HealthTab(label: '步数', route: '/health/steps'),
    _HealthTab(label: '体检', route: '/health/checkup'),
    _HealthTab(label: '报告', route: '/health/reports'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final OverviewController overview = AppScope.of(context).overview;
    if (_overview == overview) {
      return;
    }
    _overview?.healthNotifier.removeListener(_onOverviewChanged);
    _overview = overview;
    _overview!.healthNotifier.addListener(_onOverviewChanged);
    // 首次进入时总览可能已就绪（登录后已拉过），补一次 7 日统计。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _weekAvgSteps == null && !_weekStatsLoading) {
        _loadWeekAvg();
      }
    });
  }

  @override
  void dispose() {
    _overview?.healthNotifier.removeListener(_onOverviewChanged);
    super.dispose();
  }

  /// 总览刷新成功（切回健康 Tab / 下拉刷新）后同步重算 7 日均步数。
  void _onOverviewChanged() {
    if (!mounted) {
      return;
    }
    final OverviewState<HealthOverview> state = _overview!.health;
    if (state.status == LoadStatus.ready && !_weekStatsLoading) {
      _loadWeekAvg();
    }
  }

  /// 拉近 7 日统计，只取 `avg_steps`；失败时展示 `—`，不回退到总览的错误口径。
  Future<void> _loadWeekAvg() async {
    if (_weekStatsLoading) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      if (mounted) {
        setState(() {
          _weekAvgSteps = null;
          _weekStatsLoading = false;
          _weekStatsFailed = true;
        });
      }
      return;
    }
    setState(() => _weekStatsLoading = true);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/steps/stats',
            queryParameters: <String, dynamic>{'days': 7},
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '步数统计返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _weekAvgSteps = StepStats.fromJson(json).avgSteps;
        _weekStatsLoading = false;
        _weekStatsFailed = false;
      });
    } on ApiException {
      if (!mounted) {
        return;
      }
      setState(() {
        _weekStatsLoading = false;
        _weekStatsFailed = true;
      });
    }
  }

  /// 下拉刷新：总览 + 7 日均步数并发，保留旧数据直到新数据返回。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    await Future.wait<void>(<Future<void>>[
      scope.overview.refreshHealth(),
      _loadWeekAvg(),
    ]);
  }

  /// 点击域内栏目：概览留在本页，其余跳到对应子页；返回后对账一次。
  Future<void> _openTab(int index) async {
    final String? route = _tabs[index].route;
    if (route == null) {
      if (index != _activeTab) {
        setState(() => _activeTab = index);
      }
      return;
    }
    setState(() => _activeTab = index);
    await context.push(route);
    if (mounted) {
      setState(() => _activeTab = 0);
      await _refresh();
    }
  }

  /// 打开健康功能搜索；选中后跳转并刷新摘要。
  Future<void> _openSearch() async {
    final String? route = await openV2Search(
      context,
      hint: '搜索健康功能',
      sections: const <V2SearchSection>[
        V2SearchSection(
          title: '健康功能',
          entries: <V2SearchEntry>[
            V2SearchEntry(
              title: '睡眠体征',
              subtitle: '血压 · 心率 · 睡眠时长',
              icon: Icons.bedtime_outlined,
              route: '/health/vitals-sleep',
              keywords: '睡眠 睡觉 体征 血压 心率 血氧 体温',
            ),
            V2SearchEntry(
              title: '用药跟踪',
              subtitle: '今日服药与药品库存',
              icon: Icons.medication_outlined,
              route: '/health/medication',
              keywords: '用药 吃药 服药 药品 库存',
            ),
            V2SearchEntry(
              title: '健身运动',
              subtitle: '运动记录与本周次数',
              icon: Icons.fitness_center_outlined,
              route: '/health/fitness',
              keywords: '运动 健身 锻炼 跑步',
            ),
            V2SearchEntry(
              title: '饮食记录',
              subtitle: '今日摄入与餐次',
              icon: Icons.restaurant_outlined,
              route: '/health/diet',
              keywords: '饮食 吃饭 摄入 热量 餐',
            ),
            V2SearchEntry(
              title: '体重记录',
              subtitle: '体重 · BMI · 体脂',
              icon: Icons.monitor_weight_outlined,
              route: '/health/body',
              keywords: '体重 称重 体脂 BMI 蓝牙秤',
            ),
            V2SearchEntry(
              title: '步数统计',
              subtitle: '今日步数与分时段记录',
              icon: Icons.directions_walk_outlined,
              route: '/health/steps',
              keywords: '步数 走路 距离 卡路里',
            ),
            V2SearchEntry(
              title: '体检指标',
              subtitle: '体检记录与指标面板',
              icon: Icons.assignment_outlined,
              route: '/health/checkup',
              keywords: '体检 指标 面板 化验',
            ),
            V2SearchEntry(
              title: '健康报告',
              subtitle: '周期汇总与 PDF 导出',
              icon: Icons.description_outlined,
              route: '/health/reports',
              keywords: '报告 汇总 PDF 导出',
            ),
          ],
        ),
      ],
    );
    if (route != null && mounted) {
      await context.push(route);
      if (mounted) {
        await _refresh();
      }
    }
  }

  /// 打开底部快捷记录面板；选中后跳转并刷新摘要。
  Future<void> _openQuickRecord() async {
    final String? route = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (BuildContext context) => const _QuickRecordSheet(),
    );
    if (route != null && mounted) {
      await context.push(route);
      if (mounted) {
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: scope.overview.healthNotifier,
      builder: (BuildContext context, _) {
        final OverviewState<HealthOverview> state = scope.overview.health;
        final HealthOverview? data = state.data;
        final bool loading = data == null && state.status == LoadStatus.loading;

        return PopScope(
          canPop: false,
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
                      title: '健康',
                      actions: <Widget>[
                        V2IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: '搜索健康功能',
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
                            .map((_HealthTab tab) => tab.label)
                            .toList(growable: false),
                        selectedIndex: _activeTab,
                        onSelected: _openTab,
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
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
                              label: _heroLabel(data),
                              value: loading ? '…' : formatInt(data?.steps),
                              unit: loading || data?.steps == null ? null : '步',
                              subtitle: _heroSubtitle(data, state.status),
                            ),
                            const SizedBox(height: 14),
                            StatRail(
                              items: <StatRailItem>[
                                StatRailItem(
                                  label: '睡眠',
                                  value: loading
                                      ? '…'
                                      : _sleepCompact(data?.weekSleepAvgMin),
                                ),
                                StatRailItem(
                                  label: '体重',
                                  value: loading ? '…' : _weightValue(data),
                                  unit: loading || !_hasWeight(data)
                                      ? null
                                      : 'kg',
                                ),
                                StatRailItem(
                                  label: '日均步数',
                                  value: loading ? '…' : _weekAvgText(),
                                  unit: !loading && _weekAvgSteps != null
                                      ? '步'
                                      : null,
                                ),
                              ],
                            ),
                            SectionHeader(
                              title: '今日用药',
                              actionLabel: '全部',
                              onAction: () => _openTab(2),
                            ),
                            _medicationGroup(context, data, state.status),
                            SectionHeader(
                              title: '最近记录',
                              actionLabel: '报告',
                              onAction: () => _openTab(8),
                            ),
                            _recentGroup(context, data, state.status),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton(
                tooltip: '快速记录',
                onPressed: _openQuickRecord,
                shape: const CircleBorder(),
                child: const Icon(Icons.add),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Hero 标签：最新步数不是今天时改称「最近步数」，避免把旧数据当今日。
  String _heroLabel(HealthOverview? data) {
    if (data?.steps == null) {
      return '今日步数';
    }
    return _isToday(data?.stepsDate ?? '') ? '今日步数' : '最近步数';
  }

  /// Hero 副信息：优先展示距离 / 消耗，旧记录补日期，空数据给可执行引导。
  String _heroSubtitle(HealthOverview? data, LoadStatus status) {
    if (data == null) {
      return status == LoadStatus.loading ? '正在加载健康数据…' : '暂无数据，下拉刷新重试';
    }
    if (data.steps == null) {
      return '今天还没有步数记录，点右下角 + 补录';
    }
    final String date = data.stepsDate ?? '';
    if (!_isToday(date)) {
      return date.isEmpty ? '最近一次记录' : '记录于 ${formatListDate(date)}';
    }
    final double? distance = data.distanceKm;
    final int? calories = data.calories;
    final List<String> parts = <String>[
      if (distance != null) '距离 ${formatCompact(distance)} km',
      if (calories != null) '消耗 ${formatInt(calories)} 千卡',
    ];
    return parts.isEmpty ? '今日记录' : parts.join(' · ');
  }

  /// 今日用药：最多展示 3 条，完整列表在用药页；空态给出下一步入口。
  Widget _medicationGroup(
    BuildContext context,
    HealthOverview? data,
    LoadStatus status,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final List<MedicationItem> items =
        data?.medicationItems ?? const <MedicationItem>[];
    if (items.isEmpty) {
      final bool loading = data == null && status == LoadStatus.loading;
      final bool hasData = data != null;
      return GroupCard(
        children: <Widget>[
          InkWell(
            onTap: () => _openTab(2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    loading ? '正在加载今日用药…' : (hasData ? '今天没有用药安排' : '暂无用药数据'),
                    style: AppType.rowTitle.copyWith(color: tokens.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loading ? '请稍候' : (hasData ? '点击查看用药计划' : '下拉刷新或点击重试'),
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return GroupCard(
      children: <Widget>[
        for (final MedicationItem item in items.take(3))
          TaskRow(
            leading: _MedCheck(taken: item.taken),
            title: item.name.isEmpty ? '用药' : item.name,
            subtitle: (item.dosage ?? '').trim().isEmpty
                ? '今日用药'
                : item.dosage!.trim(),
            trailing: V2Badge(
              item.taken ? '已服' : '待服',
              tone: item.taken ? V2BadgeTone.gray : V2BadgeTone.info,
            ),
            onTap: () => _openTab(2),
          ),
      ],
    );
  }

  /// 最近记录：步数 / 体重 / 睡眠三条，按真实总览字段展示，不虚构时间点。
  Widget _recentGroup(
    BuildContext context,
    HealthOverview? data,
    LoadStatus status,
  ) {
    final bool loading = data == null && status == LoadStatus.loading;
    final bool unavailable = data == null && !loading;
    final int? steps = data?.steps;
    final double? weight = data?.weightKg;
    final bool hasWeight = weight != null && weight > 0;
    final String stepsDate = data?.stepsDate ?? '';
    final String weightDate = data?.weightDate ?? '';

    String stepsSubtitle;
    if (loading) {
      stepsSubtitle = '正在加载…';
    } else if (steps == null) {
      stepsSubtitle = unavailable ? '暂无数据' : '还没有记录';
    } else if (stepsDate.isEmpty) {
      stepsSubtitle = '最近一次记录';
    } else {
      stepsSubtitle = _isToday(stepsDate)
          ? '今天'
          : '记录于 ${formatListDate(stepsDate)}';
    }

    String weightSubtitle;
    if (loading) {
      weightSubtitle = '正在加载…';
    } else if (!hasWeight) {
      weightSubtitle = unavailable ? '暂无数据' : '还没有记录';
    } else if (weightDate.isEmpty) {
      weightSubtitle = '最近一次记录';
    } else {
      weightSubtitle = '记录于 ${formatListDate(weightDate)}';
    }

    return GroupCard(
      children: <Widget>[
        RecordRow(
          title: '步数',
          subtitle: stepsSubtitle,
          value: loading
              ? '…'
              : (steps == null ? '—' : '${formatInt(steps)} 步'),
          onTap: () => _openTab(6),
        ),
        RecordRow(
          title: '体重',
          subtitle: weightSubtitle,
          value: loading
              ? '…'
              : (hasWeight ? '${formatOneDecimal(weight)} kg' : '—'),
          onTap: () => _openTab(5),
        ),
        RecordRow(
          title: '睡眠',
          subtitle: loading ? '正在加载…' : '近 7 天平均',
          value: loading ? '…' : _sleepCompact(data?.weekSleepAvgMin),
          onTap: () => _openTab(1),
        ),
      ],
    );
  }

  /// 7 日均步数文案：加载中显示「…」，失败显示「—」（不展示错误口径的数值）。
  String _weekAvgText() {
    if (_weekStatsLoading && _weekAvgSteps == null) {
      return '…';
    }
    if (_weekStatsFailed && _weekAvgSteps == null) {
      return '—';
    }
    return formatInt(_weekAvgSteps);
  }

  static bool _hasWeight(HealthOverview? data) {
    final double? weight = data?.weightKg;
    return weight != null && weight > 0;
  }

  static String _weightValue(HealthOverview? data) {
    if (!_hasWeight(data)) {
      return '—';
    }
    return formatOneDecimal(data!.weightKg);
  }

  /// 睡眠时长压缩展示：`432` → `7h12m`；空值返回「—」。
  static String _sleepCompact(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return '—';
    }
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    if (hours == 0) {
      return '${rest}m';
    }
    return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
  }

  static bool _isToday(String date) {
    if (date.length < 10) {
      return false;
    }
    final DateTime now = DateTime.now();
    return date.substring(0, 10) ==
        '${now.year}-${_two(now.month)}-${_two(now.day)}';
  }

  static String _two(int value) => value < 10 ? '0$value' : '$value';
}

/// 健康域栏目的静态定义。
class _HealthTab {
  const _HealthTab({required this.label, this.route});

  final String label;
  final String? route;
}

/// 今日用药的勾选圆点：已服用 System Blue 实心，待服用空心描边。
class _MedCheck extends StatelessWidget {
  const _MedCheck({required this.taken});

  final bool taken;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: taken ? tokens.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: taken ? null : Border.all(color: tokens.line, width: 1.5),
      ),
      child: taken
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}

/// 底部快捷记录面板：只做入口，具体字段仍走原有表单，避免重复实现校验逻辑。
class _QuickRecordSheet extends StatelessWidget {
  const _QuickRecordSheet();

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
                '快速记录',
                style: AppType.rowTitle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 6),
              const _QuickRecordRow(
                icon: Icons.directions_walk_outlined,
                title: '记录步数',
                subtitle: '补录今日步数与距离',
                route: '/health/steps/new',
              ),
              const _QuickRecordRow(
                icon: Icons.monitor_weight_outlined,
                title: '记录体重',
                subtitle: '手动录入或蓝牙称重',
                route: '/health/body/new',
              ),
              const _QuickRecordRow(
                icon: Icons.medication_outlined,
                title: '用药打卡',
                subtitle: '查看今日用药并打卡',
                route: '/health/medication',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRecordRow extends StatelessWidget {
  const _QuickRecordRow({
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
