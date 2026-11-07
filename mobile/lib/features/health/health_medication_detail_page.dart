import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/queue/outbox_controller.dart';
import '../../core/queue/outbox_entry.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../finance/finance_status_widgets.dart';

/// 用药记录明细：单日记录的三餐用量与完成情况。
///
/// 数据：`GET /health/medication/{id}`；[initial] 是列表页带过来的快照，
/// 断网进入时先用它渲染，打卡仍可走本地队列，联网后刷新为服务端真实值。
class HealthMedicationDetailPage extends StatefulWidget {
  const HealthMedicationDetailPage({
    super.key,
    required this.recordId,
    this.initial,
  });

  final int recordId;

  /// 列表页已经加载过的同一条记录（离线时作为展示兜底）。
  final MedicationRecord? initial;

  @override
  State<HealthMedicationDetailPage> createState() =>
      _HealthMedicationDetailPageState();
}

class _HealthMedicationDetailPageState
    extends State<HealthMedicationDetailPage> {
  MedicationRecord? _record;
  LoadStatus _status = LoadStatus.loading;
  String? _message;
  OutboxController? _outbox;
  DateTime? _seenSyncAt;

  @override
  void initState() {
    super.initState();
    _record = widget.initial;
    _status = widget.initial == null ? LoadStatus.loading : LoadStatus.ready;
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

  /// 队列变化：刷新「待同步」标记；同步成功后再拉一次服务端真实值。
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

  /// 离线打卡：本地立即标记已服并写入队列；联网后自动 PUT 回服务端。
  ///
  /// 打卡是对既有记录的更新（`PUT /health/medication/{id}`），
  /// 同一请求体重复执行结果一致，因此重试天然幂等，不做查重。
  Future<void> _checkIn(int slot) async {
    final MedicationRecord? record = _record;
    final OutboxController? outbox = _outbox;
    if (record == null || outbox == null) {
      return;
    }
    final Map<String, dynamic> payload = <String, dynamic>{
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
    };
    final OutboxEntry? entry = await outbox.enqueueMedicationCheckin(payload);
    if (!mounted) {
      return;
    }
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('待同步已达上限（200 条），请先联网同步后再打卡'),
        ),
      );
      return;
    }
    setState(() {
      _record = record.copyWith(
        takenBreakfast: slot == 0 ? true : null,
        takenLunch: slot == 1 ? true : null,
        takenDinner: slot == 2 ? true : null,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outbox.isOnline ? '已打卡，正在同步到服务器' : '已打卡（待同步），联网后自动同步',
        ),
      ),
    );
  }

  /// 编辑该记录；保存或删除后直接返回列表，由列表重拉统计与记录。
  Future<void> _openEdit() async {
    final MedicationRecord? record = _record;
    if (record == null) {
      return;
    }
    final String? result = await context.push<String>(
      '/health/medication/${record.id}/edit',
      extra: record,
    );
    if (!mounted) {
      return;
    }
    if (result == 'saved' || result == 'deleted') {
      context.pop(true);
    }
  }

  /// 拉取单条用药记录；401/网络失败按状态分流。
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
      _status = _record == null ? LoadStatus.loading : LoadStatus.ready;
      _message = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                  '/health/medication/${widget.recordId}'))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '用药记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _record = MedicationRecord.fromJson(json);
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
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MedicationRecord? record = _record;

    return DetailPageScaffold(
      title: '用药明细',
      actions: record == null
          ? null
          : <Widget>[
              IconButton(
                tooltip: '编辑该记录',
                onPressed: _openEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
      child: ListView(
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
              if (record != null) ...<Widget>[
                SectionCard(
                  title: '用药信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: <Widget>[
                      Row(
                        spacing: 8,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              record.medicineName,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          StatusChip(
                            label: record.isComplete ? '已完成' : '未完成',
                            tone: record.isComplete
                                ? StatusTone.success
                                : StatusTone.warning,
                          ),
                          if (_outbox?.hasPendingTarget(
                                outboxOpMedicationCheckin,
                                record.id,
                              ) ??
                              false)
                            const StatusChip(
                              label: '待同步',
                              tone: StatusTone.info,
                            ),
                        ],
                      ),
                      _DetailRow(label: '日期', value: record.recordDate),
                      if (record.frequency != null)
                        _DetailRow(label: '频次', value: record.frequency!),
                      _DetailRow(
                        label: '总用量',
                        value: '${record.totalDoses} 粒/次包干',
                      ),
                      if (record.note != null && record.note!.trim().isNotEmpty)
                        _DetailRow(label: '备注', value: record.note!),
                    ],
                  ),
                ),
                SectionCard(
                  title: '三餐用量',
                  child: Column(
                    spacing: 10,
                    children: <Widget>[
                      _MealRow(
                        label: '早餐',
                        dose: record.doseBreakfast,
                        taken: record.takenBreakfast,
                        onCheckIn: () => _checkIn(0),
                      ),
                      _MealRow(
                        label: '午餐',
                        dose: record.doseLunch,
                        taken: record.takenLunch,
                        onCheckIn: () => _checkIn(1),
                      ),
                      _MealRow(
                        label: '晚餐',
                        dose: record.doseDinner,
                        taken: record.takenDinner,
                        onCheckIn: () => _checkIn(2),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 明细字段行：左标签右值。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// 单餐行：餐次 + 粒数 + 已服/未服；未服时可直接打卡（离线走队列）。
class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.label,
    required this.dose,
    required this.taken,
    required this.onCheckIn,
  });

  final String label;
  final int dose;
  final bool taken;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      spacing: 12,
      children: <Widget>[
        SizedBox(width: 44, child: Text(label, style: theme.textTheme.bodyMedium)),
        Expanded(
          child: Text(
            dose == 0 ? '无需服用' : '$dose 粒',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (dose == 0)
          const StatusChip(label: '—', tone: StatusTone.info)
        else if (taken)
          const StatusChip(label: '已服', tone: StatusTone.success)
        else
          FilledButton.tonal(
            onPressed: onCheckIn,
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('打卡'),
          ),
      ],
    );
  }
}
