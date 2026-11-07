import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 步数录入 / 编辑：日期 + 时间段 + 步数。
///
/// - 新增：`POST /health/steps`，底部整行宽「保存」。
/// - 编辑：`PUT /health/steps/{id}`，底部「左保存、右删除」，删除二次确认。
///
/// 字段与网页端一致：`record_date` / `period` / `steps`；
/// 距离与消耗由后端按步幅自动计算，编辑时回传原记录的 `stride_cm`，
/// 避免按默认 70cm 重算导致距离口径漂移。
///
/// 为什么不做离线队列：步数录入的诉求是「录完立刻看到汇总变化」，
/// 而后端没有幂等键，排队重试可能重复入库（同一天同一时段会被 409 拦下，
/// 但用户得回队列里手动处理）；在线提交失败时用户就在表单前，可直接重试。
class HealthStepsCreatePage extends StatefulWidget {
  const HealthStepsCreatePage({
    super.key,
    this.recordId,
    this.initial,
  });

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，用于打开即预填；为空时按 [recordId] 拉取。
  final StepRecord? initial;

  @override
  State<HealthStepsCreatePage> createState() => _HealthStepsCreatePageState();
}

class _HealthStepsCreatePageState extends State<HealthStepsCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _steps = TextEditingController();

  DateTime _date = DateTime.now();
  String _period = _periodForNow();
  StepRecord? _record;

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.recordId != null;

  /// 当前小时落在哪个时段；凌晨归到最早的 08-09（与网页端一致）。
  static String _periodForNow() {
    final int hour = DateTime.now().hour;
    if (hour >= 23) {
      return '23-24';
    }
    if (hour < 8) {
      return '08-09';
    }
    final String value = '$hour-${hour + 1}';
    return kStepPeriods.any(
          (({String value, String label}) item) => item.value == value,
        )
        ? value
        : 'full';
  }

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final StepRecord? initial = widget.initial;
      if (initial != null) {
        _apply(initial);
      } else {
        _loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadRecord();
          }
        });
      }
    }
  }

  /// 用一条记录预填表单（日期 / 时段 / 步数）。
  void _apply(StepRecord record) {
    _record = record;
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _period = record.period;
    _steps.text = '${record.steps}';
  }

  /// 编辑模式兜底：没有快照时按 id 取最新记录。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/steps/${widget.recordId}'))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '步数记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(StepRecord.fromJson(json));
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  @override
  void dispose() {
    _steps.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd`（后端 `record_date` 口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择录入日期。
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _date = picked);
  }

  /// 提交：新增走 POST、编辑走 PUT；409（同日期同时段已存在）在表单内提示并保留输入。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：步数录入需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'period': _period,
      'steps': int.parse(_steps.text.trim()),
    };
    // 编辑时沿用原步幅，让后端按同一口径重算距离与热量。
    final double? stride = _record?.strideCm;
    if (stride != null) {
      payload['stride_cm'] = stride;
    }
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/steps/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/steps',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? '已保存 $_dateText ${stepPeriodLabel(_period)} '
                    '${_steps.text.trim()} 步'
                : '已保存 ${stepPeriodLabel(_period)} ${_steps.text.trim()} 步',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message.contains('已存在')
            ? '$_dateText 已存在 ${stepPeriodLabel(_period)} 的记录，请换个时间段'
            : error.message;
      });
    }
  }

  /// 删除：二次确认说明影响范围，成功后返回列表刷新统计。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该时段记录？'),
          content: Text(
            '将删除 $_dateText ${stepPeriodLabel(_period)} 的 '
            '${_steps.text.trim()} 步记录。\n'
            '删除后当天汇总、日均与分时段分布会同步回退，且无法恢复。',
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
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await scope.apiClient.delete<dynamic>('/health/steps/${widget.recordId}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该时段记录')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int steps = int.tryParse(_steps.text.trim()) ?? 0;
    return DetailPageScaffold(
      title: _editing ? '编辑步数' : '新增步数',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: <Widget>[
                      SectionCard(
                        title: _editing ? '修改时段记录' : '步数信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            _FieldTile(
                              label: '日期',
                              value: _dateText,
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickDate,
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _period,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: '时间段'),
                              items: <DropdownMenuItem<String>>[
                                for (final ({String value, String label}) item
                                    in kStepPeriods)
                                  DropdownMenuItem<String>(
                                    value: item.value,
                                    child: Text(item.label),
                                  ),
                                // 历史数据可能用了选项外的时段值，原样保留避免下拉断言。
                                if (!kStepPeriods.any(
                                  (({String value, String label}) item) =>
                                      item.value == _period,
                                ))
                                  DropdownMenuItem<String>(
                                    value: _period,
                                    child: Text(_period),
                                  ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) {
                                  setState(() => _period = value);
                                }
                              },
                            ),
                            TextFormField(
                              controller: _steps,
                              autofocus: !_editing,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '步数',
                                hintText: '例如 3200',
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (String? value) {
                                final int? parsed =
                                    int.tryParse((value ?? '').trim());
                                if (parsed == null || parsed < 0) {
                                  return '请输入不小于 0 的整数步数';
                                }
                                return null;
                              },
                            ),
                            Text(
                              '预计距离 ${(steps * 70 / 100000).toStringAsFixed(2)} km · '
                              '消耗 ${(steps * 0.04).toStringAsFixed(1)} kcal',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      if (_editing)
                        AppActionRow(
                          first: AppPrimaryButton(
                            label: '保存',
                            icon: Icons.save_outlined,
                            loading: _saving,
                            onPressed: _deleting ? null : _save,
                          ),
                          second: AppDangerButton(
                            label: '删除',
                            loading: _deleting,
                            onPressed: _saving || _deleting ? null : _delete,
                          ),
                        )
                      else
                        AppPrimaryButton(
                          label: '保存',
                          icon: Icons.save_outlined,
                          loading: _saving,
                          onPressed: _save,
                        ),
                      Text(
                        _editing
                            ? '保存与删除均在线提交；删除后当天汇总、日均与时段分布会立即刷新。'
                            : '保存后列表与区间汇总会立即刷新；同一天同一时间段的记录不能重复添加。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

/// 只读字段行（日期等），点击后交给上层弹选择器。
class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(value)),
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
