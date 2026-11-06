import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';
import '../finance/finance_status_widgets.dart';

/// 用药记录明细：单日记录的三餐用量与完成情况。
///
/// 数据：`GET /health/medication/{id}`。
class HealthMedicationDetailPage extends StatefulWidget {
  const HealthMedicationDetailPage({super.key, required this.recordId});

  final int recordId;

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
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
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
              if (_status == LoadStatus.ready && record != null) ...<Widget>[
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
                      ),
                      _MealRow(
                        label: '午餐',
                        dose: record.doseLunch,
                        taken: record.takenLunch,
                      ),
                      _MealRow(
                        label: '晚餐',
                        dose: record.doseDinner,
                        taken: record.takenDinner,
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

/// 单餐行：餐次 + 粒数 + 已服/未服。
class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.label,
    required this.dose,
    required this.taken,
  });

  final String label;
  final int dose;
  final bool taken;

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
        StatusChip(
          label: dose == 0 ? '—' : (taken ? '已服' : '未服'),
          tone: dose == 0
              ? StatusTone.info
              : (taken ? StatusTone.success : StatusTone.warning),
        ),
      ],
    );
  }
}
