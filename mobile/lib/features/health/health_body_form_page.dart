import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 体重录入 / 编辑：日期 + 体重（必填）+ 体脂率 / 肌肉率 / 身高（可选）。
///
/// - 新增：`POST /health/body`，底部整行宽「保存」；
/// - 编辑：`PUT /health/body/{id}`，底部「左保存、右删除」，删除二次确认。
///
/// 与网页端 `/health/body` 口径一致：
/// - 同一天重复录入是**新增**一条（只有蓝牙同步才会覆盖当天记录）；
/// - 身高与体重都有值时按 `体重 / 身高(m)²` 计算 BMI（保留 1 位小数）并提交；
///   编辑时若身高被清空，同时把 BMI 置空，避免留下按旧身高算出的陈旧值。
/// - 体脂率 / 肌肉率 / 身高留空提交 null；后端把 0 视作「未采集」，
///   因此输入 0 按非法值拦截，不回传 0 污染数据。
class HealthBodyFormPage extends StatefulWidget {
  const HealthBodyFormPage({
    super.key,
    this.recordId,
    this.initial,
  });

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，用于打开即预填；为空时按 [recordId] 拉取。
  final BodyRecord? initial;

  @override
  State<HealthBodyFormPage> createState() => _HealthBodyFormPageState();
}

class _HealthBodyFormPageState extends State<HealthBodyFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _bodyFat = TextEditingController();
  final TextEditingController _muscle = TextEditingController();
  final TextEditingController _height = TextEditingController();

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
      final BodyRecord? initial = widget.initial;
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

  /// 用一条记录预填表单（只回填本页维护的字段）。
  void _apply(BodyRecord record) {
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _weight.text = record.weightKg == null ? '' : _plain(record.weightKg!);
    _bodyFat.text =
        record.bodyFatPercent == null ? '' : _plain(record.bodyFatPercent!);
    _muscle.text =
        record.musclePercent == null ? '' : _plain(record.musclePercent!);
    _height.text = record.heightCm == null ? '' : _plain(record.heightCm!);
  }

  /// `74.00` → `74`、`22.30` → `22.3`，避免预填出现多余小数位。
  String _plain(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// 编辑模式兜底：没有快照时按 id 取最新记录。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/body/${widget.recordId}'))
          .data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '体重记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(BodyRecord.fromJson(json));
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
    _weight.dispose();
    _bodyFat.dispose();
    _muscle.dispose();
    _height.dispose();
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

  /// 可空数值字段：留空返回 null，非法输入交给校验器拦截。
  double? _optional(TextEditingController controller) {
    final String text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 提交：新增走 POST、编辑走 PUT；失败保留输入便于修正。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：体重录入需要联网，请恢复网络后重试');
      return;
    }
    final double? weight = _optional(_weight);
    final double? bodyFat = _optional(_bodyFat);
    final double? muscle = _optional(_muscle);
    final double? height = _optional(_height);
    final double? bmi = (height == null || weight == null)
        ? null
        : (weight / ((height / 100) * (height / 100)) * 10).round() / 10;
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'weight_kg': weight,
    };
    // 编辑时显式回传 null，允许把历史误采集的字段清空；新增时留空即不提交。
    if (_editing) {
      payload['body_fat_percent'] = bodyFat;
      payload['muscle_percent'] = muscle;
      payload['height_cm'] = height;
      payload['bmi'] = bmi;
    } else {
      if (bodyFat != null) {
        payload['body_fat_percent'] = bodyFat;
      }
      if (muscle != null) {
        payload['muscle_percent'] = muscle;
      }
      if (height != null) {
        payload['height_cm'] = height;
      }
      if (bmi != null) {
        payload['bmi'] = bmi;
      }
    }
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/body/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/body',
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
                ? '已更新 $_dateText 的体重记录'
                : '已保存 $_dateText · ${weight!.toStringAsFixed(1)} kg',
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

  /// 删除：二次确认说明影响范围，成功后返回列表刷新统计。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该条体重记录？'),
          content: Text(
            '将删除 $_dateText 的体重记录。\n'
            '删除后概览（当前体重 / BMI / 平均体重）与体重趋势会同步回退，且无法恢复。',
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
      await scope.apiClient.delete<dynamic>('/health/body/${widget.recordId}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条体重记录')));
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
    final double? weight = _optional(_weight);
    final double? height = _optional(_height);
    final double? bmi = (weight == null || height == null)
        ? null
        : weight / ((height / 100) * (height / 100));
    return DetailPageScaffold(
      title: _editing ? '编辑体重' : '新增体重',
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
                      ? '保存后概览与趋势会同步更新，删除会回退统计。'
                      : '同一天可录入多条；保存后概览与趋势会更新。',
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
                        title: _editing ? '修改体重记录' : '体重信息',
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
                            TextFormField(
                              controller: _weight,
                              autofocus: !_editing,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '体重（必填）',
                                hintText: '例如 74.7',
                                suffixText: 'kg',
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (String? value) {
                                final double? parsed =
                                    double.tryParse((value ?? '').trim());
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的体重';
                                }
                                if (parsed > 500) {
                                  return '体重超出合理范围（≤ 500 kg）';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _bodyFat,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '体脂率（可选）',
                                hintText: '例如 22.3',
                                suffixText: '%',
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (String? value) =>
                                  _validatePercent(value, '体脂率'),
                            ),
                            TextFormField(
                              controller: _muscle,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '肌肉率（可选）',
                                hintText: '—',
                                suffixText: '%',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (String? value) =>
                                  _validatePercent(value, '肌肉率'),
                            ),
                            TextFormField(
                              controller: _height,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '身高（可选，用于算 BMI）',
                                hintText: '例如 173',
                                suffixText: 'cm',
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (String? value) {
                                final String text = (value ?? '').trim();
                                if (text.isEmpty) {
                                  return null;
                                }
                                final double? parsed = double.tryParse(text);
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的身高';
                                }
                                if (parsed < 50 || parsed > 300) {
                                  return '身高应在 50~300 cm';
                                }
                                return null;
                              },
                            ),
                            Text(
                              bmi == null
                                  ? '填身高与体重后自动计算 BMI；留空字段不会写入 0。'
                                  : 'BMI ${bmi.toStringAsFixed(1)}'
                                      '（按 ${weight!.toStringAsFixed(1)} kg / '
                                      '${height!.toStringAsFixed(0)} cm 自动计算）',
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
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// 百分比字段校验：留空合法；填写必须是 0~100 之间的正数（0 视为未采集，拦截）。
  String? _validatePercent(String? value, String label) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) {
      return '请输入大于 0 的$label';
    }
    if (parsed > 100) {
      return '$label不应超过 100';
    }
    return null;
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
