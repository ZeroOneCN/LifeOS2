import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/list_load_more_footer.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_status.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../shared/widgets/v2/v2_segmented.dart';
import '../../theme/app_tokens.dart';

/// 用药跟踪：今日服药与依从率 + 分餐次 + 药品库存 + 用药记录分页。
///
/// 数据：
/// - `GET /health/medication/stats?days=7`
/// - `GET /health/medication?page=&page_size=20`
/// - `GET /health/medication/stocks`
class HealthMedicationPage extends StatefulWidget {
  const HealthMedicationPage({super.key});

  @override
  State<HealthMedicationPage> createState() => _HealthMedicationPageState();
}

class _HealthMedicationPageState extends State<HealthMedicationPage> {
  final List<MedicationRecord> _items = <MedicationRecord>[];

  MedicationStats? _stats;
  List<MedStock> _stocks = const <MedStock>[];
  List<MedPurchase> _purchases = const <MedPurchase>[];
  int _purchaseTotal = 0;
  String? _purchaseError;
  int _lowCount = 0;
  LoadStatus _status = LoadStatus.loading;
  String? _message;

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 当前栏目：0 = 今日，1 = 库存，2 = 购药，3 = 记录。
  int _tab = 0;

  /// 近 7 天已服粒数合计（依从率分子）。
  int get _windowTaken =>
      _stats?.bySlot.fold<int>(0, (int sum, MedSlot slot) => sum + slot.taken) ??
      0;

  /// 近 7 天计划粒数合计（依从率分母）；为 0 时依从率显示「—」。
  int get _windowTotal =>
      _stats?.bySlot.fold<int>(0, (int sum, MedSlot slot) => sum + slot.total) ??
      0;

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

  /// 首屏/重试：并行拉统计、库存与第一页记录，任一失败整体失败。
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
      final Future<Map<String, dynamic>?> statsFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/health/medication/stats',
            queryParameters: <String, dynamic>{'days': 7},
          )
          .then((value) => value.data);
      final Future<Map<String, dynamic>?> listFuture = scope.apiClient
          .get<Map<String, dynamic>>(
            '/health/medication',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 20},
          )
          .then((value) => value.data);
      final Future<Map<String, dynamic>?> stocksFuture = scope.apiClient
          .get<Map<String, dynamic>>('/health/medication/stocks')
          .then((value) => value.data);
      final List<Map<String, dynamic>?> responses = await Future.wait(
        <Future<Map<String, dynamic>?>>[statsFuture, listFuture, stocksFuture],
      );
      final Map<String, dynamic>? statsJson = responses[0];
      final Map<String, dynamic>? listJson = responses[1];
      final Map<String, dynamic>? stocksJson = responses[2];
      if (statsJson == null || listJson == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '用药接口返回数据为空',
        );
      }
      final List<MedicationRecord> items = _parseItems(listJson);
      final List<MedStock> stocks =
          ((stocksJson?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (Map item) => MedStock.fromJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = MedicationStats.fromJson(statsJson);
        _stocks = stocks;
        _lowCount = (stocksJson?['low_count'] as num?)?.toInt() ?? 0;
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
      final bool offline =
          scope.auth.hasLocalSession &&
          (error.kind == ApiErrorKind.network ||
              error.kind == ApiErrorKind.timeout);
      setState(() {
        _status = error.isUnauthorized
            ? LoadStatus.unauthenticated
            : (offline ? LoadStatus.connectionFailed : LoadStatus.failed);
        _message = error.message;
      });
    }
    // 购药记录单独请求：失败只影响该区块，不拖垮整页。
    if (mounted) {
      await _loadPurchases();
    }
  }

  /// 拉取最近 5 条购药记录；失败只在区块内提示。
  Future<void> _loadPurchases() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      return;
    }
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/medication/purchases',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 5},
          )).data;
      final List<MedPurchase> items =
          ((json?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (Map item) =>
                    MedPurchase.fromJson(item.cast<String, dynamic>()),
              )
              .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _purchases = items;
        _purchaseTotal = (json?['total'] as num?)?.toInt() ?? items.length;
        _purchaseError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _purchaseError = error.message);
    }
  }

  /// 加载更多用药记录；失败只提示，不清空已加载数据。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/medication',
            queryParameters: <String, dynamic>{
              'page': _page + 1,
              'page_size': 20,
            },
          )).data;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载更多失败：${error.message}')));
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 从分页响应中取出 `items` 并转为 [MedicationRecord]。
  List<MedicationRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (Map item) => MedicationRecord.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
  }

  /// 打开新增用药页；保存成功返回后立即重拉列表与今日统计。
  ///
  /// 表单保存后 pop 的是 `'saved'` 字符串（详情页编辑同样用它区分已保存），
  /// 这里必须按字符串接收，否则类型不匹配拿到 null，列表不会刷新。
  Future<void> _openCreate() async {
    final String? result = await context.push<String>('/health/medication/new');
    if (result == 'saved' && mounted) {
      await _refresh();
    }
  }

  /// 打开用药明细；在明细里编辑或删除后返回 `true`，这里重拉全部统计。
  Future<void> _openDetail(MedicationRecord record) async {
    final bool? changed = await context.push<bool>(
      '/health/medication/${record.id}',
      extra: record,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 新增 / 编辑药品库存；保存或删除后重拉库存与低库存计数。
  Future<void> _openStock([MedStock? stock]) async {
    final bool? changed = stock == null
        ? await context.push<bool>('/health/medication/stocks/new')
        : await context.push<bool>(
            '/health/medication/stocks/${stock.id}/edit',
            extra: stock,
          );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 打开新增购药记录；保存后重拉库存（后端会同步补货）与购药列表。
  Future<void> _openPurchase() async {
    final bool? created = await context.push<bool>(
      '/health/medication/purchases/new',
    );
    if (created == true && mounted) {
      await _refresh();
    }
  }

  /// 编辑购药记录：带快照进入表单，保存后重拉库存与购药列表。
  Future<void> _openPurchaseEdit(MedPurchase purchase) async {
    final bool? changed = await context.push<bool>(
      '/health/medication/purchases/${purchase.id}',
      extra: purchase,
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 删除购药记录：确认后删除，并重拉购药列表与库存提醒。
  Future<void> _deletePurchase(MedPurchase purchase) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该条购药记录？'),
          content: Text(
            '将删除 ${purchase.buyDate}「${purchase.medicineName}」的购药记录。\n'
            '删除后购药总额与低库存提醒会同步更新，且无法恢复。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              second: AppDangerButton(
                label: '删除',
                compact: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await scope.apiClient.delete<dynamic>(
        '/health/medication/purchases/${purchase.id}',
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条购药记录')));
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('删除购药记录失败：${error.message}')),
      );
    }
  }

  /// 列表内快速打卡：弹层列出早/午/晚，点未服的一餐直接提交。
  ///
  /// 之前打卡入口只在详情页，用户在列表看不到；这里把入口放到记录行上，
  /// 同时保留详情页入口。已打卡的餐次不再重复提交。
  Future<void> _openCheckIn(MedicationRecord record) async {
    final List<({int slot, String label, int dose, bool taken})> slots =
        <({int slot, String label, int dose, bool taken})>[
          (
            slot: 0,
            label: '早餐',
            dose: record.doseBreakfast,
            taken: record.takenBreakfast,
          ),
          (
            slot: 1,
            label: '午餐',
            dose: record.doseLunch,
            taken: record.takenLunch,
          ),
          (
            slot: 2,
            label: '晚餐',
            dose: record.doseDinner,
            taken: record.takenDinner,
          ),
        ];
    final int? selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${record.medicineName} · ${record.recordDate}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final ({int slot, String label, int dose, bool taken}) item
                  in slots)
                if (item.dose > 0)
                  ListTile(
                    leading: Icon(
                      item.taken
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: item.taken
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(item.label),
                    subtitle: Text('${item.dose} 粒'),
                    trailing: item.taken
                        ? Text(
                            '已服',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : FilledButton.tonal(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(item.slot),
                            child: const Text('打卡'),
                          ),
                  ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      await _checkIn(record, selected);
    }
  }

  /// 列表内打卡：直接提交 `PUT /health/medication/{id}`。
  Future<void> _checkIn(MedicationRecord record, int slot) async {
    final bool alreadyTaken = switch (slot) {
      0 => record.takenBreakfast,
      1 => record.takenLunch,
      _ => record.takenDinner,
    };
    if (alreadyTaken) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    try {
      await scope.apiClient.put<Map<String, dynamic>>(
        '/health/medication/${record.id}',
        data: <String, dynamic>{
          'id': record.id,
          'record_date': record.recordDate,
          'medicine_name': record.medicineName,
          'dose_breakfast': record.doseBreakfast,
          'dose_lunch': record.doseLunch,
          'dose_dinner': record.doseDinner,
          'taken_breakfast': slot == 0 ? true : record.takenBreakfast,
          'taken_lunch': slot == 1 ? true : record.takenLunch,
          'taken_dinner': slot == 2 ? true : record.takenDinner,
          if (record.frequency != null) 'frequency': record.frequency,
          if (record.note != null) 'note': record.note,
        },
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打卡失败。${describeWriteFailure(error)}')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已打卡')));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final MedicationStats? stats = _stats;
    return DetailPageScaffold(
      title: '用药跟踪',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (stats == null)
            Expanded(
              child: ListPageBody(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            )
          else ...<Widget>[
            // 刷新失败但仍有旧数据：保留内容，顶部提示可重试。
            if (_status != LoadStatus.ready && _status != LoadStatus.idle)
              OverviewStatusBanner(
                status: _status,
                message: _message,
                onRetry: _refresh,
              ),
            SummaryStrip(
              caption: '今日已服 ${formatInt(stats.todayTaken)} 粒 · '
                  '待服 ${formatInt(stats.todayPending)} 粒 · '
                  '记录 ${formatInt(stats.totalCount)} 条',
              items: <StatRailItem>[
                StatRailItem(
                  label: '今日已服',
                  value: formatInt(stats.todayTaken),
                  unit: '粒',
                  color: tokens.green,
                ),
                StatRailItem(
                  label: '今日待服',
                  value: formatInt(stats.todayPending),
                  unit: '粒',
                  color: stats.todayPending > 0 ? tokens.orange : null,
                ),
                StatRailItem(
                  label: '7 日依从率',
                  value: _windowTotal == 0
                      ? '—'
                      : formatPercent(stats.adherenceRate),
                ),
              ],
            ),
            V2Segmented<int>(
              options: const <V2SegmentedOption<int>>[
                V2SegmentedOption<int>(label: '今日', value: 0),
                V2SegmentedOption<int>(label: '库存', value: 1),
                V2SegmentedOption<int>(label: '购药', value: 2),
                V2SegmentedOption<int>(label: '记录', value: 3),
              ],
              selected: _tab,
              onChanged: (int index) => setState(() => _tab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: <Widget>[
                  _todayTab(tokens, stats),
                  _stockTab(tokens),
                  _purchaseTab(tokens),
                  _recordTab(tokens),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「今日」栏目：今日已服 / 待服、7 日依从率与近 7 天餐次完成度。
  Widget _todayTab(AppTokens tokens, MedicationStats stats) {
    final bool noTodayPlan =
        stats.todayTaken == 0 && stats.todayPending == 0;
    final String basis = _windowTotal == 0
        ? '口径：今日已服 / 待服按「粒」统计；近 7 天没有计划剂量，依从率暂记「—」。'
        : '口径：今日已服 / 待服按「粒」统计；7 日依从率 = 近 7 天已服 '
              '${formatInt(_windowTaken)} / 计划 ${formatInt(_windowTotal)} 粒，'
              '今日尚未到点的剂量不计为失败。';
    return ListView(
      key: const PageStorageKey<String>('health-medication-today'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '今日用药',
          actionLabel: '新增用药',
          onAction: _openCreate,
        ),
        GroupCard(
          children: <Widget>[
            RecordRow(
              title: '今日已服',
              subtitle: '按「粒」统计',
              value: '${formatInt(stats.todayTaken)} 粒',
              valueColor: tokens.green,
            ),
            RecordRow(
              title: '今日待服',
              subtitle: '按「粒」统计',
              value: '${formatInt(stats.todayPending)} 粒',
              valueColor: stats.todayPending > 0 ? tokens.orange : null,
            ),
            RecordRow(
              title: '7 日依从率',
              subtitle: '已服 ${formatInt(_windowTaken)} / '
                  '计划 ${formatInt(_windowTotal)} 粒',
              value: _windowTotal == 0
                  ? '—'
                  : formatPercent(stats.adherenceRate),
            ),
            RecordRow(
              title: '累计记录',
              subtitle: '全部用药记录',
              value: '${formatInt(stats.totalCount)} 条',
            ),
            RecordRow(
              title: '累计服药',
              subtitle: '全部记录合计',
              value: '${formatInt(stats.totalPills)} 粒',
            ),
            if (stats.bySlot.any((MedSlot slot) => slot.total > slot.taken))
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    V2Badge('有未服用的餐次', tone: V2BadgeTone.warn),
                  ],
                ),
              ),
          ],
        ),
        const SectionHeader(title: '近 7 天餐次完成度'),
        GroupCard(
          children: stats.bySlot.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.medication_outlined,
                    title: '暂无餐次统计',
                    description: '近 7 天还没有用药计划',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final MedSlot slot in stats.bySlot) _SlotRow(slot: slot),
                ],
        ),
        const SizedBox(height: 12),
        Text(
          noTodayPlan
              ? '$basis\n今日暂无用药计划，下方依从率统计的是近 7 天数据。'
              : basis,
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 「库存」栏目：药品余量 / 预警值 / 预计用完，点按行编辑。
  Widget _stockTab(AppTokens tokens) {
    return ListView(
      key: const PageStorageKey<String>('health-medication-stock'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '药品库存 · 共 ${formatInt(_stocks.length)} 项',
          actionLabel: '新增药品',
          onAction: () => _openStock(),
        ),
        GroupCard(
          children: <Widget>[
            if (_stocks.isEmpty)
              const EmptyState(
                icon: Icons.medication_outlined,
                title: '暂无药品库存',
                description: '点「新增药品」登记库存',
                compact: true,
              )
            else ...<Widget>[
              if (_lowCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      V2Badge('$_lowCount 项偏低', tone: V2BadgeTone.warn),
                    ],
                  ),
                ),
              for (final MedStock stock in _stocks)
                _StockRow(stock: stock, onTap: () => _openStock(stock)),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '余量低于预警值会标为「库存偏低」，点按行可修改库存。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 「购药」栏目：最近 5 条购药记录，可编辑 / 删除。
  Widget _purchaseTab(AppTokens tokens) {
    return ListView(
      key: const PageStorageKey<String>('health-medication-purchase'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        if (_purchaseError != null)
          V2ErrorBanner(message: '购药记录加载失败：$_purchaseError'),
        SectionHeader(
          title: '购药记录 · 共 ${formatInt(_purchaseTotal)} 条',
          actionLabel: '记录购药',
          onAction: _openPurchase,
        ),
        GroupCard(
          children: _purchases.isEmpty
              ? const <Widget>[
                  EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: '暂无购药记录',
                    description: '点「记录购药」登记补货',
                    compact: true,
                  ),
                ]
              : <Widget>[
                  for (final MedPurchase purchase in _purchases)
                    _PurchaseRow(
                      purchase: purchase,
                      onEdit: () => _openPurchaseEdit(purchase),
                      onDelete: () => _deletePurchase(purchase),
                    ),
                ],
        ),
        const SizedBox(height: 12),
        Text(
          '保存购药后库存会按数量自动补货，删除记录会同步撤销补货。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }

  /// 「记录」栏目：用药记录分页，支持行内快捷打卡。
  Widget _recordTab(AppTokens tokens) {
    return ListView(
      key: const PageStorageKey<String>('health-medication-record'),
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[
        SectionHeader(
          title: '用药记录 · 共 ${formatInt(_total)} 条',
          actionLabel: '新增用药',
          onAction: _openCreate,
        ),
        GroupCard(
          children: <Widget>[
            if (_items.isEmpty)
              const EmptyState(
                icon: Icons.medication_outlined,
                title: '暂无用药记录',
                description: '点「新增用药」添加今天的用药计划',
                compact: true,
              )
            else
              for (final MedicationRecord record in _items)
                _RecordRow(
                  record: record,
                  onTap: () => _openDetail(record),
                  onCheckIn: () => _openCheckIn(record),
                ),
          ],
        ),
        if (_items.isNotEmpty)
          ListLoadMoreFooter(
            loading: _loadingMore,
            hasMore: _hasMore,
            onPressed: _loadMore,
          ),
        const SizedBox(height: 12),
        Text(
          '点按行查看明细；未完成的记录可直接在行内打卡。',
          style: AppType.rowMeta.copyWith(color: tokens.text3),
        ),
      ],
    );
  }
}

/// 餐次完成度行：餐次 + 进度条 + 已服 / 计划粒数。
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot});

  final MedSlot slot;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              child: Text(
                slot.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowTitle.copyWith(color: tokens.text),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: slot.total == 0 ? 0 : slot.taken / slot.total,
                  minHeight: 6,
                  backgroundColor: tokens.fill2,
                  color: tokens.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${formatInt(slot.taken)}/${formatInt(slot.total)}',
              maxLines: 1,
              softWrap: false,
              style: AppType.rowValue.copyWith(
                color: slot.total > slot.taken ? tokens.orange : tokens.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 库存行：药品名（含低库存徽标）+ 余量 / 预警 / 预计用完 → 约 N 天。
class _StockRow extends StatelessWidget {
  const _StockRow({required this.stock, required this.onTap});

  final MedStock stock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // 余量与预警放一行；预计用完单独一行，避免长文案在行尾被拆成单个字。
    final String meta = <String>[
      '余量 ${_trim(stock.quantity)} ${stock.unit}',
      if (stock.threshold > 0) '预警 ${_trim(stock.threshold)} ${stock.unit}',
    ].join(' · ');
    final String? predicted = stock.predictedDate == null
        ? null
        : '预计 ${formatListDate(stock.predictedDate)} 用完';
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
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            stock.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.rowTitle.copyWith(
                              color: tokens.text,
                            ),
                          ),
                        ),
                        if (stock.isLow) ...<Widget>[
                          const SizedBox(width: 6),
                          const V2Badge(
                            '库存偏低',
                            tone: V2BadgeTone.danger,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowMeta.copyWith(color: tokens.text2),
                    ),
                    if (predicted != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        predicted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowMeta.copyWith(color: tokens.text2),
                      ),
                    ],
                  ],
                ),
              ),
              if (stock.daysLeft != null) ...<Widget>[
                const SizedBox(width: 12),
                Text(
                  '约 ${formatInt(stock.daysLeft)} 天',
                  maxLines: 1,
                  softWrap: false,
                  style: AppType.rowValue.copyWith(
                    color: stock.isLow ? tokens.red : tokens.text,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 15, color: tokens.text3),
            ],
          ),
        ),
      ),
    );
  }

  /// 去掉小数的整数显示（20.0 → 20）。
  String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

/// 购药记录行：药名 + 日期 / 数量 / 渠道 → 总价与更多操作（编辑 / 删除）。
class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.purchase,
    required this.onEdit,
    required this.onDelete,
  });

  final MedPurchase purchase;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String unit = purchase.unit ?? '盒';
    final String meta = <String>[
      formatListDate(purchase.buyDate),
      '${_trim(purchase.quantity)} $unit',
      if ((purchase.channel ?? '').trim().isNotEmpty) purchase.channel!.trim(),
    ].join(' · ');
    return ConstrainedBox(
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
                    purchase.medicineName,
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
            Text(
              formatMoney(purchase.totalPrice),
              maxLines: 1,
              softWrap: false,
              style: AppType.rowValue.copyWith(
                color: purchase.totalPrice == null ? tokens.text3 : tokens.text,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: Icon(Icons.more_horiz, size: 18, color: tokens.text3),
              padding: EdgeInsets.zero,
              onSelected: (String value) {
                if (value == 'edit') {
                  onEdit();
                } else {
                  onDelete();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('编辑'),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('删除', style: TextStyle(color: tokens.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 去掉无意义的尾零（2.0 → 2）。
  String _trim(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

/// 用药记录行：药名 + 完成徽标 + 日期 / 三餐用量 → 已服 / 应服与打卡入口。
class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.onTap,
    required this.onCheckIn,
  });

  final MedicationRecord record;
  final VoidCallback onTap;

  /// 快捷打卡回调：打开早/午/晚选择弹层。
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final int takenDoses = record.takenDoses;
    final bool complete = record.isComplete;
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
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            record.medicineName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.rowTitle.copyWith(
                              color: tokens.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        V2Badge(
                          complete ? '已完成' : '未完成',
                          tone: complete
                              ? V2BadgeTone.green
                              : V2BadgeTone.warn,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatListDate(record.recordDate)} · '
                      '早 ${record.doseBreakfast} 午 ${record.doseLunch} '
                      '晚 ${record.doseDinner}',
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
                    '${formatInt(takenDoses)}/${formatInt(record.totalDoses)}',
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.rowValue.copyWith(color: tokens.text),
                  ),
                  if (record.totalDoses > 0 && !complete)
                    TextButton(
                      onPressed: onCheckIn,
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.accent,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: AppType.action.copyWith(fontSize: 13),
                      ),
                      child: const Text('打卡'),
                    ),
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
}
