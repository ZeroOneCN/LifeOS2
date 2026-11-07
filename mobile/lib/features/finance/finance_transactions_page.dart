import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/queue/outbox_controller.dart';
import '../../core/queue/outbox_entry.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/add_record_fab.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 流水页：本轮先落地「离线队列 + 最近支出」两段。
///
/// - **待同步**：本地队列（`OutboxController`），断网保存后立刻出现，
///   带「待同步」标记；推送失败显示错误并提供「立即同步」。
/// - **最近支出**：服务端 `GET /finance/shopping/records` 前 5 条，
///   队列推送成功后自动刷新，用来确认真实数据已补上。
///
/// 完整的流水分页列表留到后续批次，本页不做横向/分页处理。
class FinanceTransactionsPage extends StatefulWidget {
  const FinanceTransactionsPage({super.key});

  @override
  State<FinanceTransactionsPage> createState() =>
      _FinanceTransactionsPageState();
}

class _FinanceTransactionsPageState extends State<FinanceTransactionsPage> {
  OutboxController? _outbox;
  DateTime? _seenSyncAt;

  final List<ShoppingRecord> _records = <ShoppingRecord>[];
  bool _loading = true;
  String? _loadError;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRecords();
      }
    });
  }

  @override
  void dispose() {
    _outbox?.removeListener(_onOutboxChanged);
    super.dispose();
  }

  /// 队列变化：刷新待同步段；若同步成功过（`lastSyncAt` 前进）再拉服务端列表。
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
      _loadRecords(silent: true);
    }
  }

  /// 拉最近 5 条支出；[silent] 时保留旧数据，失败只在页内提示。
  Future<void> _loadRecords({bool silent = false}) async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _loadError = '未登录，登录后显示服务端支出';
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
        '/finance/shopping/records',
        queryParameters: <String, dynamic>{'page': 1, 'page_size': 5},
      ))
          .data;
      if (!mounted) {
        return;
      }
      final List<dynamic> items =
          json?['items'] as List<dynamic>? ?? <dynamic>[];
      setState(() {
        _records
          ..clear()
          ..addAll(
            items
                .whereType<Map>()
                .map((Map item) =>
                    ShoppingRecord.fromJson(item.cast<String, dynamic>()))
                .toList(),
          );
        _loading = false;
        _loadError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppScope scope = AppScope.of(context);
    return DetailPageScaffold(
      title: '流水',
      floatingActionButton: const AddRecordFab(),
      child: ListenableBuilder(
        listenable: scope.outbox,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            // 底部预留悬浮「记一笔」按钮的安全距离。
            padding: const EdgeInsets.only(bottom: 120),
            children: <Widget>[
              // 后端当前只有消费支出记录，没有收入流水；先把口径讲清楚。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _hint(
                  theme,
                  Icons.info_outline,
                  '口径：当前仅包含消费支出（来自购物记录），收入流水暂未接入。',
                ),
              ),
              const SizedBox(height: 12),
              _pendingCard(theme, scope.outbox),
              const SizedBox(height: 12),
              _recentCard(theme),
            ],
          );
        },
      ),
    );
  }

  /// 待同步卡片：只展示财务支出条目 + 失败原因 + 自动重试状态。
  Widget _pendingCard(ThemeData theme, OutboxController outbox) {
    final List<OutboxEntry> entries =
        outbox.pendingOf(outboxOpCreateExpense);
    final OutboxEntry? head = entries.isEmpty ? null : entries.first;
    final bool headIsExpense =
        outbox.entries.isNotEmpty &&
        outbox.entries.first.opType == outboxOpCreateExpense;
    return SectionCard(
      title: '待同步',
      trailing: Text(
        '共 ${entries.length} 条',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: <Widget>[
          if (!outbox.isOnline)
            _hint(theme, Icons.cloud_off_outlined, '当前无网络，恢复后自动同步'),
          if (head?.lastError != null)
            _hint(
              theme,
              Icons.error_outline,
              '上次推送失败：${head!.lastError}',
              color: theme.colorScheme.error,
            ),
          if (headIsExpense && outbox.nextRetryAt != null)
            _hint(
              theme,
              Icons.schedule_outlined,
              '下次自动重试：${_hm(outbox.nextRetryAt!)}',
            ),
          if (headIsExpense && outbox.needsManualRetry)
            _hint(
              theme,
              Icons.error_outline,
              '自动重试已达上限，请手动重试',
              color: theme.colorScheme.error,
            ),
          if (entries.isEmpty)
            Text(
              '暂无待同步记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final OutboxEntry entry in entries)
              _PendingRow(entry: entry),
          if (entries.isNotEmpty)
            Row(
              spacing: 8,
              children: <Widget>[
                Expanded(
                  child: Text(
                    outbox.isSyncing ? '正在同步…' : '按入队顺序推送，失败即停',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: outbox.isSyncing || !outbox.isOnline
                      ? null
                      : outbox.retryNow,
                  child: const Text('立即同步'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 最近支出卡片：服务端前 5 条，确认队列推送后真实数据补上。
  Widget _recentCard(ThemeData theme) {
    return SectionCard(
      title: '最近支出',
      trailing: TextButton(
        onPressed: _loading ? null : _loadRecords,
        child: const Text('刷新'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_loadError != null)
            _hint(theme, Icons.error_outline, _loadError!, color: theme.colorScheme.error),
          if (!_loading && _loadError == null && _records.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '暂无支出记录',
              description: '保存一笔支出后，同步成功即可在这里看到',
              compact: true,
            ),
          for (final ShoppingRecord record in _records)
            _RecentRow(record: record),
        ],
      ),
    );
  }

  /// 页内提示条：图标 + 文案，可选错误色。
  Widget _hint(
    ThemeData theme,
    IconData icon,
    String text, {
    Color? color,
  }) {
    final Color contentColor =
        color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: 8,
      children: <Widget>[
        Icon(icon, size: 18, color: contentColor),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: contentColor),
          ),
        ),
      ],
    );
  }
}

/// `HH:mm`：展示自动重试时间。
String _hm(DateTime time) {
  final DateTime local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// 队列条目行：金额右对齐、等宽；状态标记「待同步」/「同步失败」。
class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.entry});

  final OutboxEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = entry.payload['product_name'] as String? ?? '';
    final String date = entry.payload['record_date'] as String? ?? '';
    final num? amount = entry.payload['total_price'] as num?;
    final bool failed = entry.lastError != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(
                  name.isEmpty ? '未命名支出' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    _StatusChip(failed: failed),
                  ],
                ),
                if (failed)
                  Text(
                    entry.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatMoney(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 待同步 / 同步失败 标记。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        failed ? theme.colorScheme.error : theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        failed ? '同步失败' : '待同步',
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// 服务端最近支出行。
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record});

  final ShoppingRecord record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 12,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(
                  record.productName.isEmpty ? '未命名支出' : record.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  record.recordDate,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(record.totalPrice),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
