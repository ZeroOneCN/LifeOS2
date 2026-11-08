import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 睡眠记录录入 / 编辑。
///
/// 字段与网页端 `/health/vitals-sleep` 记录表一致：
/// 日期、入睡/起床时间、血压高低值、心率、血氧、血糖、体温、
/// 深睡/浅睡时长、醒来次数、备注。
///
/// - 新增：`POST /health/vitals-sleep`；编辑：`PUT /health/vitals-sleep/{id}`；
/// - 删除：`DELETE /health/vitals-sleep/{id}`（仅编辑态可见，二次确认写明统计影响）。
///
/// 空值口径：
/// - 所有可选字段留空一律提交 null，不写 0；展示时由各页统一显示「—」；
/// - 睡眠时长不在表单里手填，交给后端按入睡/起床时间计算（跨零点自动加一天）。
class HealthSleepFormPage extends StatefulWidget {
  const HealthSleepFormPage({super.key, this.recordId, this.initial});

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，打开即预填；为空时按 [recordId] 拉取。
  final SleepRecord? initial;

  @override
  State<HealthSleepFormPage> createState() => _HealthSleepFormPageState();
}

class _HealthSleepFormPageState extends State<HealthSleepFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _bedtime = TextEditingController();
  final TextEditingController _wakeTime = TextEditingController();
  final TextEditingController _bpHigh = TextEditingController();
  final TextEditingController _bpLow = TextEditingController();
  final TextEditingController _heartRate = TextEditingController();
  final TextEditingController _bloodOxygen = TextEditingController();
  final TextEditingController _bloodGlucose = TextEditingController();
  final TextEditingController _bodyTemp = TextEditingController();
  final TextEditingController _deepSleep = TextEditingController();
  final TextEditingController _lightSleep = TextEditingController();
  final TextEditingController _wakeCount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final SleepRecord? initial = widget.initial;
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

  @override
  void dispose() {
    _bedtime.dispose();
    _wakeTime.dispose();
    _bpHigh.dispose();
    _bpLow.dispose();
    _heartRate.dispose();
    _bloodOxygen.dispose();
    _bloodGlucose.dispose();
    _bodyTemp.dispose();
    _deepSleep.dispose();
    _lightSleep.dispose();
    _wakeCount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用一条记录预填表单：未采集字段留空，展示时不写 0。
  void _apply(SleepRecord record) {
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _bedtime.text = record.bedtime ?? '';
    _wakeTime.text = record.wakeTime ?? '';
    _bpHigh.text = _plainInt(record.bloodPressureHigh);
    _bpLow.text = _plainInt(record.bloodPressureLow);
    _heartRate.text = _plainInt(record.heartRate);
    _bloodOxygen.text = _plainDouble(record.bloodOxygen);
    _bloodGlucose.text = _plainDouble(record.bloodGlucose);
    _bodyTemp.text = _plainDouble(record.bodyTemp);
    _deepSleep.text = _plainInt(record.deepSleepMin);
    _lightSleep.text = _plainInt(record.lightSleepMin);
    _wakeCount.text = _plainInt(record.wakeCount);
    _note.text = record.note ?? '';
  }

  String _plainInt(int? value) => value == null ? '' : '$value';

  /// `22.30` → `22.3`，避免预填出现多余小数位。
  String _plainDouble(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// 编辑模式兜底：没有快照时按 id 取最新记录。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/vitals-sleep/${widget.recordId}',
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '睡眠记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(SleepRecord.fromJson(json));
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

  /// 选择时间，输出 `HH:mm`；已填值时以当前值为初始时间。
  Future<void> _pickTime(TextEditingController controller) async {
    final List<String> parts = controller.text.split(':');
    final int hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 23 : 23;
    final int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: hour.clamp(0, 23),
        minute: minute.clamp(0, 59),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    String two(int value) => value < 10 ? '0$value' : '$value';
    setState(
      () => controller.text = '${two(picked.hour)}:${two(picked.minute)}',
    );
  }

  /// 清空时间输入：控制器清空后重建以隐藏右侧清空按钮。
  void _clearTime(TextEditingController controller) {
    controller.clear();
    setState(() {});
  }

  /// 可空整数：留空返回 null，不做 0 兜底。
  int? _optionalInt(TextEditingController controller) {
    final String text = controller.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  /// 可空小数：留空返回 null，不做 0 兜底。
  double? _optionalDouble(TextEditingController controller) {
    final String text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 可空文本：全空白按未填处理。
  String? _optionalText(TextEditingController controller) {
    final String text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// 提交：新增走 POST、编辑走 PUT；失败保留输入便于修正。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.connectivity.isOnline) {
      setState(() => _error = '当前无网络：睡眠记录需要联网保存，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'bedtime': _optionalText(_bedtime),
      'wake_time': _optionalText(_wakeTime),
      'blood_pressure_high': _optionalInt(_bpHigh),
      'blood_pressure_low': _optionalInt(_bpLow),
      'heart_rate': _optionalInt(_heartRate),
      'blood_oxygen': _optionalDouble(_bloodOxygen),
      'blood_glucose': _optionalDouble(_bloodGlucose),
      'body_temp': _optionalDouble(_bodyTemp),
      'deep_sleep_min': _optionalInt(_deepSleep),
      'light_sleep_min': _optionalInt(_lightSleep),
      'wake_count': _optionalInt(_wakeCount),
      'note': _optionalText(_note),
      // 显式置 null 让后端按入睡/起床时间重算；两端都清空时同时清掉旧时长。
      'sleep_duration_min': null,
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/vitals-sleep/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/vitals-sleep',
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
            _editing ? '已更新 $_dateText 的睡眠记录' : '已保存 $_dateText 的睡眠记录',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  /// 删除：二次确认写明对概览、分阶段均值与趋势的影响。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除该条睡眠记录？'),
          content: Text(
            '将删除 $_dateText 的睡眠记录。\n'
            '删除后睡眠概览（平均时长 / 平均质量）、分阶段均值与趋势都会同步回退，且无法恢复。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppDangerButton(
                label: '删除',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
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
      await scope.apiClient.delete<dynamic>(
        '/health/vitals-sleep/${widget.recordId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条睡眠记录')));
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
    return DetailPageScaffold(
      title: _editing ? '编辑睡眠' : '新增睡眠',
      bottomBar: _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
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
                const SizedBox(height: 6),
                Text(
                  _editing
                      ? '保存后睡眠概览、分阶段均值与趋势会同步更新；留空字段按未采集处理。'
                      : '睡眠时长由入睡/起床时间自动计算；留空字段不会写入 0。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
                        title: _editing ? '修改睡眠记录' : '睡眠信息',
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
                            _TimeField(
                              controller: _bedtime,
                              label: '入睡时间（可选）',
                              onPick: () => _pickTime(_bedtime),
                              onClear: () => _clearTime(_bedtime),
                            ),
                            _TimeField(
                              controller: _wakeTime,
                              label: '起床时间（可选）',
                              onPick: () => _pickTime(_wakeTime),
                              onClear: () => _clearTime(_wakeTime),
                            ),
                            TextFormField(
                              controller: _bpHigh,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '血压高压（可选）',
                                hintText: '例如 120',
                                suffixText: 'mmHg',
                              ),
                              validator: (String? value) =>
                                  _validateInt(value, '血压高压', 20, 300),
                            ),
                            TextFormField(
                              controller: _bpLow,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '血压低压（可选）',
                                hintText: '例如 80',
                                suffixText: 'mmHg',
                              ),
                              validator: (String? value) =>
                                  _validateInt(value, '血压低压', 20, 300),
                            ),
                            TextFormField(
                              controller: _heartRate,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '心率（可选）',
                                hintText: '例如 62',
                                suffixText: 'bpm',
                              ),
                              validator: (String? value) =>
                                  _validateInt(value, '心率', 20, 300),
                            ),
                            TextFormField(
                              controller: _bloodOxygen,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '血氧（可选）',
                                hintText: '例如 98',
                                suffixText: '%',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '血氧', 1, 100),
                            ),
                            TextFormField(
                              controller: _bloodGlucose,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '血糖（可选）',
                                hintText: '例如 5.6',
                                suffixText: 'mmol/L',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '血糖', 0, 50),
                            ),
                            TextFormField(
                              controller: _bodyTemp,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '体温（可选）',
                                hintText: '例如 36.5',
                                suffixText: '℃',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '体温', 30, 45),
                            ),
                            TextFormField(
                              controller: _deepSleep,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '深睡时长（可选）',
                                hintText: '例如 95',
                                suffixText: '分钟',
                              ),
                              validator: (String? value) =>
                                  _validateInt(value, '深睡时长', 0, 1440),
                            ),
                            TextFormField(
                              controller: _lightSleep,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '浅睡时长（可选）',
                                hintText: '例如 240',
                                suffixText: '分钟',
                              ),
                              validator: (String? value) =>
                                  _validateInt(value, '浅睡时长', 0, 1440),
                            ),
                            TextFormField(
                              controller: _wakeCount,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '醒来次数（可选）',
                                hintText: '例如 2',
                                suffixText: '次',
                              ),
                              validator: (String? value) =>
                                  _validateInt(value, '醒来次数', 0, 99),
                            ),
                            TextFormField(
                              controller: _note,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: '备注（可选）',
                                hintText: '例如 睡前喝咖啡',
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
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// 可空整数校验：留空合法；填写必须是 [min, max] 内的整数。
  String? _validateInt(String? value, String label, int min, int max) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final int? parsed = int.tryParse(text);
    if (parsed == null) {
      return '$label 请填整数';
    }
    if (parsed < min || parsed > max) {
      return '$label 应在 $min~$max';
    }
    return null;
  }

  /// 可空小数校验：留空合法；填写必须在 [min, max] 区间内。
  /// [min] 为 0 时仍不接受 0（0 表示未采集，请留空）。
  String? _validateDouble(String? value, String label, double min, double max) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return '$label 请填数字';
    }
    if (parsed < min || parsed > max || (min == 0 && parsed == 0)) {
      return '$label 应在 $min~$max 之间；未采集请留空';
    }
    return null;
  }
}

/// 只读日期行，点击交给上层弹日期选择器。
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

/// 只读时间行：点击弹时间选择器，右侧提供清空。
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.controller,
    required this.label,
    required this.onPick,
    required this.onClear,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool filled = controller.text.isNotEmpty;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                filled ? controller.text : '未填',
                style: filled
                    ? null
                    : TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (filled)
              InkWell(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.schedule,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
