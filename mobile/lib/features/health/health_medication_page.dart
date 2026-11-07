import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/queue/outbox_controller.dart';
import '../../core/queue/outbox_entry.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../finance/finance_status_widgets.dart';

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

  OutboxController? _outbox;
  DateTime? _seenSyncAt;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final OutboxController outbox = AppScope.of(context).outbox;
    if (_outbox == outbox) {
      return;
    }
    _outbox?.removeListener(_onOutboxChanged);
    _outbox = outbox;
    _seenSyncAt = outbox.lastSyncAt;
    outbox.addListener(_onOutboxChanged);
  }

  @override
  void dispose() {
    _outbox?.removeListener(_onOutboxChanged);
    super.dispose();
  }

  /// 队列变化：刷新待同步标记；同步成功后重新拉取服务端真实数据。
  void _onOutboxChanged() {
    if (!mounted) {
      return;
    }
    final DateTime? syncAt = _outbox?.lastSyncAt;
    final bool syncAdvanced = syncAt != null && syncAt != _seenSyncAt;
    if (syncAdvanced) {
      _seenSyncAt = syncAt;
    }
    setState(() {});
    if (syncAdvanced) {
      _refresh();
    }
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
      final List<Map<String, dynamic>?> responses =
          await Future.wait(<Future<Map<String, dynamic>?>>[
        statsFuture,
        listFuture,
        stocksFuture,
      ]);
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
              .map((Map item) => MedStock.fromJson(item.cast<String, dynamic>()))
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
      final bool offline = scope.auth.hasLocalSession &&
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
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/medication/purchases',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 5},
              ))
          .data;
      final List<MedPurchase> items =
          ((json?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map item) =>
                  MedPurchase.fromJson(item.cast<String, dynamic>()))
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
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/medication',
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

  /// 从分页响应中取出 `items` 并转为 [MedicationRecord]。
  List<MedicationRecord> _parseItems(Map<String, dynamic> json) {
    return ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map item) =>
            MedicationRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 打开新增用药页；保存成功返回后立即重拉列表与今日统计。
  Future<void> _openCreate() async {
    final bool? created = await context.push<bool>('/health/medication/new');
    if (created == true && mounted) {
      _refresh();
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
    final bool? created =
        await context.push<bool>('/health/medication/purchases/new');
    if (created == true && mounted) {
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

  /// 列表内快速打卡：弹层列出早/午/晚，点未服的一餐直接入队。
  ///
  /// 之前打卡入口只在详情页，用户在列表看不到；这里把入口放到记录行上，
  /// 同时保留详情页入口。已打卡的餐次不再重复提交。
  Future<void> _openCheckIn(MedicationRecord record) async {
    final Map<String, dynamic>? pending =
        _outbox?.pendingPayloadFor(outboxOpMedicationCheckin, record.id);
    final List<({int slot, String label, int dose, bool taken})> slots =
        <({int slot, String label, int dose, bool taken})>[
      (
        slot: 0,
        label: '早餐',
        dose: record.doseBreakfast,
        taken: (pending?['taken_breakfast'] as bool?) ?? record.takenBreakfast,
      ),
      (
        slot: 1,
        label: '午餐',
        dose: record.doseLunch,
        taken: (pending?['taken_lunch'] as bool?) ?? record.takenLunch,
      ),
      (
        slot: 2,
        label: '晚餐',
        dose: record.doseDinner,
        taken: (pending?['taken_dinner'] as bool?) ?? record.takenDinner,
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

  /// 列表内打卡：以队列里的最新已服状态为基准，避免覆盖掉待同步的餐次。
  Future<void> _checkIn(MedicationRecord record, int slot) async {
    final OutboxController? outbox = _outbox;
    if (outbox == null) {
      return;
    }
    final Map<String, dynamic>? pending =
        outbox.pendingPayloadFor(outboxOpMedicationCheckin, record.id);
    final bool breakfast =
        (pending?['taken_breakfast'] as bool?) ?? record.takenBreakfast;
    final bool lunch = (pending?['taken_lunch'] as bool?) ?? record.takenLunch;
    final bool dinner =
        (pending?['taken_dinner'] as bool?) ?? record.takenDinner;
    final bool alreadyTaken = switch (slot) {
      0 => breakfast,
      1 => lunch,
      _ => dinner,
    };
    if (alreadyTaken) {
      return;
    }
    final OutboxEntry? entry = await outbox.enqueueMedicationCheckin(
      <String, dynamic>{
        'id': record.id,
        'record_date': record.recordDate,
        'medicine_name': record.medicineName,
        'dose_breakfast': record.doseBreakfast,
        'dose_lunch': record.doseLunch,
        'dose_dinner': record.doseDinner,
        'taken_breakfast': slot == 0 ? true : breakfast,
        'taken_lunch': slot == 1 ? true : lunch,
        'taken_dinner': slot == 2 ? true : dinner,
        if (record.frequency != null) 'frequency': record.frequency,
        if (record.note != null) 'note': record.note,
      },
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          entry == null
              ? '待同步已达上限（200 条），请先联网同步后再打卡'
              : (outbox.isOnline
                  ? '已打卡，正在同步到服务器'
                  : '已打卡（待同步），联网后自动同步'),
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final MedicationStats? stats = _stats;

    return DetailPageScaffold(
      title: '用药跟踪',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('新增用药'),
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 72),
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
                  title: '今日用药',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 16,
                        children: <Widget>[
                          Expanded(
                            child: MetricPlaceholder(
                              label: '已服',
                              value: '${stats.todayTaken} 次',
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '待服',
                              value: '${stats.todayPending} 次',
                            ),
                          ),
                          Expanded(
                            child: MetricPlaceholder(
                              label: '7 日依从率',
                              value: formatPercent(stats.adherenceRate),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          StatusChip(
                            label: '记录 ${stats.totalCount} 条',
                            tone: StatusTone.info,
                          ),
                          StatusChip(
                            label: '累计 ${stats.totalPills} 粒',
                            tone: StatusTone.info,
                          ),
                          if (stats.bySlot.any((MedSlot slot) =>
                              slot.total > slot.taken))
                            StatusChip(
                              label: '有未服用的餐次',
                              tone: StatusTone.warning,
                            ),
                        ],
                      ),
                      if (stats.bySlot.isNotEmpty)
                        Column(
                          spacing: 8,
                          children: <Widget>[
                            for (final MedSlot slot in stats.bySlot)
                              Row(
                                spacing: 10,
                                children: <Widget>[
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      slot.label,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: slot.total == 0
                                            ? 0
                                            : slot.taken / slot.total,
                                        minHeight: 6,
                                        backgroundColor: theme.colorScheme
                                            .surfaceContainerHighest,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${slot.taken}/${slot.total}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: muted,
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '药品库存',
                  trailing: _lowCount > 0
                      ? StatusChip(
                          label: '$_lowCount 项偏低',
                          tone: StatusTone.warning,
                        )
                      : Text(
                          '${_stocks.length} 项',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: <Widget>[
                      if (_stocks.isEmpty)
                        const EmptyState(
                          icon: Icons.medication_outlined,
                          title: '暂无药品库存',
                          description: '点下方「新增药品」登记库存',
                          compact: true,
                        )
                      else
                        for (final MedStock stock in _stocks)
                          _StockRow(
                            stock: stock,
                            onTap: () => _openStock(stock),
                          ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppPrimaryAction(
                          label: '新增药品',
                          onPressed: () => _openStock(),
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '购药记录',
                  trailing: Text(
                    '共 $_purchaseTotal 条',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 4,
                    children: <Widget>[
                      if (_purchaseError != null)
                        Text(
                          '购药记录加载失败：$_purchaseError',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        )
                      else if (_purchases.isEmpty)
                        const EmptyState(
                          icon: Icons.shopping_bag_outlined,
                          title: '暂无购药记录',
                          description: '点下方「记录购药」登记补货',
                          compact: true,
                        )
                      else
                        for (final MedPurchase purchase in _purchases)
                          _PurchaseRow(
                            purchase: purchase,
                            onDelete: () => _deletePurchase(purchase),
                          ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppPrimaryAction(
                          label: '记录购药',
                          onPressed: _openPurchase,
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '用药记录',
                  trailing: Text(
                    '共 $_total 条',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.medication_outlined,
                          title: '暂无用药记录',
                          description: '点右下「新增用药」添加今天的用药计划',
                          compact: true,
                        )
                      : Column(
                          spacing: 4,
                          children: <Widget>[
                            for (final MedicationRecord record in _items)
                              _RecordRow(
                                record: record,
                                pending: _outbox?.pendingPayloadFor(
                                  outboxOpMedicationCheckin,
                                  record.id,
                                ),
                                onTap: () => _openDetail(record),
                                onCheckIn: () => _openCheckIn(record),
                              ),
                          ],
                        ),
                ),
                if (_items.isNotEmpty)
                  _MedFooter(
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

/// 库存行：名称 + 余量/预警值 + 预计可用天数；点按进入编辑/删除。
class _StockRow extends StatelessWidget {
  const _StockRow({required this.stock, required this.onTap});

  final MedStock stock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Row(
                    spacing: 6,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          stock.name,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (stock.isLow)
                        const StatusChip(
                          label: '库存偏低',
                          tone: StatusTone.danger,
                        ),
                    ],
                  ),
                  Text(
                    '余量 ${_trim(stock.quantity)} ${stock.unit} · '
                    '预警 ${_trim(stock.threshold)} ${stock.unit}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: <Widget>[
                if (stock.daysLeft != null)
                  Text(
                    '约 ${stock.daysLeft} 天',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: stock.isLow ? theme.colorScheme.error : muted,
                    ),
                  ),
                if (stock.predictedDate != null)
                  Text(
                    stock.predictedDate!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
            Icon(Icons.chevron_right, size: 18, color: muted),
          ],
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

/// 购药记录行：日期 / 药品 / 数量 / 总价 + 删除入口。
class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase, required this.onDelete});

  final MedPurchase purchase;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String unit = purchase.unit ?? '盒';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 8,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(
                  purchase.medicineName,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${purchase.buyDate} · '
                  '${_trim(purchase.quantity)} $unit'
                  '${purchase.channel == null ? '' : ' · ${purchase.channel}'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          if (purchase.totalPrice != null)
            Text(
              formatMoney(purchase.totalPrice!),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          IconButton(
            tooltip: '删除购药记录',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: theme.colorScheme.error,
            ),
          ),
        ],
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

/// 用药记录行：日期/药名 + 早中晚用量 + 完成状态 + 待同步标记。
///
/// [pending] 为本地待同步的打卡请求体：有值时按它覆盖已服状态，
/// 让列表在断网时也能立即反映用户的打卡，不必等服务器。
class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.onTap,
    required this.onCheckIn,
    this.pending,
  });

  final MedicationRecord record;
  final VoidCallback onTap;

  /// 快捷打卡回调：打开早/午/晚选择弹层。
  final VoidCallback onCheckIn;
  final Map<String, dynamic>? pending;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Map<String, dynamic>? local = pending;
    final bool takenBreakfast =
        (local?['taken_breakfast'] as bool?) ?? record.takenBreakfast;
    final bool takenLunch =
        (local?['taken_lunch'] as bool?) ?? record.takenLunch;
    final bool takenDinner =
        (local?['taken_dinner'] as bool?) ?? record.takenDinner;
    final int takenDoses =
        (takenBreakfast ? record.doseBreakfast : 0) +
        (takenLunch ? record.doseLunch : 0) +
        (takenDinner ? record.doseDinner : 0);
    final bool complete =
        record.totalDoses > 0 && takenDoses >= record.totalDoses;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          spacing: 12,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: <Widget>[
                  Row(
                    spacing: 6,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          record.medicineName,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StatusChip(
                        label: complete ? '已完成' : '未完成',
                        tone: complete ? StatusTone.success : StatusTone.warning,
                      ),
                      if (local != null)
                        const StatusChip(
                          label: '待同步',
                          tone: StatusTone.info,
                        ),
                    ],
                  ),
                  Text(
                    '${record.recordDate} · '
                    '早 ${record.doseBreakfast} 午 ${record.doseLunch} '
                    '晚 ${record.doseDinner}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '$takenDoses/${record.totalDoses}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                if (record.totalDoses > 0 && !complete)
                  TextButton(
                    onPressed: onCheckIn,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('打卡'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「加载更多 / 已全部加载」页脚。
class _MedFooter extends StatelessWidget {
  const _MedFooter({
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
