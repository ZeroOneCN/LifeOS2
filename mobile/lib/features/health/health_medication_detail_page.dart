import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/stat_rail.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

/// 用药记录明细：单日记录的三餐用量与完成情况。
///
/// 数据：`GET /health/medication/{id}`；[initial] 是列表页带过来的快照，
/// 断网进入时先用它渲染，打卡直接请求服务端，失败按网络 / 服务端错误提示。
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

  /// 打卡：直接 `PUT /health/medication/{id}`，失败按网络 / 服务端错误分别提示。
  Future<void> _checkIn(int slot) async {
    final MedicationRecord? record = _record;
    if (record == null) {
      return;
    }
    final AppScope scope = AppScope.of(context);
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
    try {
      await scope.apiClient.put<Map<String, dynamic>>(
        '/health/medication/${record.id}',
        data: payload,
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
    setState(() {
      _record = record.copyWith(
        takenBreakfast: slot == 0 ? true : null,
        takenLunch: slot == 1 ? true : null,
        takenDinner: slot == 2 ? true : null,
      );
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已打卡')));
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
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/medication/${widget.recordId}',
          )).data;
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
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final MedicationRecord? record = _record;

    return DetailPageScaffold(
      title: '用药明细',
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _refresh,
        blocks: <Widget>[
          if (record != null) ...<Widget>[
            SummaryStrip(
              caption: '${formatListDate(record.recordDate)} · '
                  '早餐 ${record.doseBreakfast} / 午餐 ${record.doseLunch} / '
                  '晚餐 ${record.doseDinner} 粒',
              items: <StatRailItem>[
                StatRailItem(
                  label: '总用量',
                  value: formatInt(record.totalDoses),
                  unit: '粒',
                ),
                StatRailItem(
                  label: '已服',
                  value: formatInt(record.takenDoses),
                  unit: '粒',
                  color: tokens.green,
                ),
                StatRailItem(
                  label: '待服',
                  value: formatInt(record.totalDoses - record.takenDoses),
                  unit: '粒',
                  color: record.isComplete ? null : tokens.orange,
                ),
              ],
            ),
            SectionHeader(
              title: '用药信息',
              actionLabel: '编辑',
              onAction: _openEdit,
            ),
            GroupCard(
              children: <Widget>[
                TaskRow(
                  title: record.medicineName,
                  trailing: V2Badge(
                    record.isComplete ? '已完成' : '未完成',
                    tone: record.isComplete
                        ? V2BadgeTone.green
                        : V2BadgeTone.warn,
                  ),
                ),
                _DetailRow(label: '日期', value: record.recordDate),
                if (record.frequency != null)
                  _DetailRow(label: '频次', value: record.frequency!),
                _DetailRow(
                  label: '总用量',
                  value: '${record.totalDoses} 粒/次包干',
                ),
                if (record.note != null && record.note!.trim().isNotEmpty)
                  _DetailRow(label: '备注', value: record.note!.trim()),
              ],
            ),
            const SectionHeader(title: '三餐用量'),
            GroupCard(
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
            Text(
              '点「打卡」会把该餐次记为已服；编辑或删除后会返回列表并刷新统计。',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ],
        ],
      ),
    );
  }
}

/// 明细字段行：左标签（次要字色）右值（主字色，可换行）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppType.rowMeta.copyWith(color: tokens.text2)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppType.rowTitle.copyWith(color: tokens.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单餐行：餐次 + 粒数 → 已服徽标 / 打卡入口。
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
    final AppTokens tokens = AppTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 44,
              child: Text(
                label,
                maxLines: 1,
                style: AppType.rowTitle.copyWith(color: tokens.text),
              ),
            ),
            Expanded(
              child: Text(
                dose == 0 ? '无需服用' : '$dose 粒',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowMeta.copyWith(color: tokens.text2),
              ),
            ),
            if (dose == 0)
              const V2Badge('—')
            else if (taken)
              const V2Badge('已服', tone: V2BadgeTone.green)
            else
              TextButton(
                onPressed: onCheckIn,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: AppType.action.copyWith(fontSize: 13),
                ),
                child: const Text('打卡'),
              ),
          ],
        ),
      ),
    );
  }
}
