import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增 / 编辑用药记录：日期 + 药品名 + 早/午/晚粒数 + 已服状态 + 备注。
///
/// 新增走 `POST /health/medication`；编辑走 `PUT /health/medication/{id}`
/// （后端 `exclude_unset` 部分更新，未展示的 `frequency` 不会被清空）。
///
/// 所有写操作均直连服务端（移动端离线队列已下线）：
/// 新增/编辑失败时按「网络错误 / 服务端错误」明确提示，不静默失败。
class HealthMedicationCreatePage extends StatefulWidget {
  const HealthMedicationCreatePage({super.key, this.recordId, this.initial});

  /// 为空表示新增；有值表示编辑该记录。
  final int? recordId;

  /// 详情页带过来的快照；为空时按 [recordId] 拉取。
  final MedicationRecord? initial;

  bool get isEdit => recordId != null;

  @override
  State<HealthMedicationCreatePage> createState() =>
      _HealthMedicationCreatePageState();
}

class _HealthMedicationCreatePageState extends State<HealthMedicationCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _breakfast = TextEditingController(text: '0');
  final TextEditingController _lunch = TextEditingController(text: '0');
  final TextEditingController _dinner = TextEditingController(text: '0');
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();
  bool _takenBreakfast = false;
  bool _takenLunch = false;
  bool _takenDinner = false;
  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final MedicationRecord? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _bootstrap();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _breakfast.dispose();
    _lunch.dispose();
    _dinner.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用快照预填编辑表单。
  void _apply(MedicationRecord record) {
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _name.text = record.medicineName;
    _breakfast.text = '${record.doseBreakfast}';
    _lunch.text = '${record.doseLunch}';
    _dinner.text = '${record.doseDinner}';
    _note.text = record.note ?? '';
    _takenBreakfast = record.takenBreakfast;
    _takenLunch = record.takenLunch;
    _takenDinner = record.takenDinner;
  }

  /// 编辑模式下若没有列表快照，则按 id 拉取一次；新增模式无需请求。
  Future<void> _bootstrap() async {
    if (!widget.isEdit || widget.initial != null) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
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
        _apply(MedicationRecord.fromJson(json));
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

  /// 选择用药日期。
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

  /// 校验三餐粒数并解析；不合法时返回 null。
  ({int breakfast, int lunch, int dinner})? _doses() {
    final int? breakfast = int.tryParse(_breakfast.text.trim());
    final int? lunch = int.tryParse(_lunch.text.trim());
    final int? dinner = int.tryParse(_dinner.text.trim());
    if (breakfast == null || lunch == null || dinner == null) {
      setState(() => _error = '早/午/晚粒数请填整数');
      return null;
    }
    if (breakfast + lunch + dinner <= 0) {
      setState(() => _error = '早/午/晚至少有一餐粒数大于 0');
      return null;
    }
    return (breakfast: breakfast, lunch: lunch, dinner: dinner);
  }

  /// 提交：新增 POST / 编辑 PUT，成功后返回 `saved` 让列表与统计刷新。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.connectivity.isOnline) {
      setState(() => _error = '当前无网络：保存用药记录需要联网，请恢复网络后重试');
      return;
    }
    final ({int breakfast, int lunch, int dinner})? doses = _doses();
    if (doses == null) {
      return;
    }
    final String note = _note.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'medicine_name': _name.text.trim(),
      'dose_breakfast': doses.breakfast,
      'dose_lunch': doses.lunch,
      'dose_dinner': doses.dinner,
      // 粒数为 0 的餐次不可能「已服」，统一回落为 false。
      'taken_breakfast': doses.breakfast > 0 && _takenBreakfast,
      'taken_lunch': doses.lunch > 0 && _takenLunch,
      'taken_dinner': doses.dinner > 0 && _takenDinner,
      'note': note.isEmpty ? null : note,
    };
    try {
      if (widget.isEdit) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/medication/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/medication',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop('saved');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? '已保存 ${_name.text.trim()}（$_dateText）'
                : '已添加 ${_name.text.trim()}（$_dateText）',
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

  /// 删除：确认文案写明今日统计与 7 日依从率会一起回退。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该条用药记录？'),
          content: Text(
            '将删除「${_name.text.trim()}」$_dateText 的记录。\n'
            '删除后今日已服 / 待服统计与 7 日依从率会同步回退，且无法恢复。',
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
      await scope.apiClient
          .delete<dynamic>('/health/medication/${widget.recordId}');
      if (!mounted) {
        return;
      }
      navigator.pop('deleted');
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条用药记录')));
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
    final int total =
        (int.tryParse(_breakfast.text.trim()) ?? 0) +
        (int.tryParse(_lunch.text.trim()) ?? 0) +
        (int.tryParse(_dinner.text.trim()) ?? 0);
    final bool busy = _loading || _saving || _deleting;
    return DetailPageScaffold(
      title: widget.isEdit ? '编辑用药' : '新增用药',
      bottomBar: widget.isEdit
          ? AppActionRow(
              first: AppPrimaryButton(
                label: '保存',
                loading: _saving,
                onPressed: busy ? null : _save,
              ),
              second: AppDangerButton(
                label: '删除',
                loading: _deleting,
                onPressed: busy ? null : _delete,
              ),
            )
          : SizedBox(
              height: kAppButtonHeight,
              width: double.infinity,
              child: AppPrimaryButton(
                label: '保存',
                loading: _saving,
                onPressed: busy ? null : _save,
              ),
            ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      SectionCard(
                        title: '用药信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _name,
                              autofocus: !widget.isEdit,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '药品名称',
                                hintText: '例如：维生素D、降压片',
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '请填写药品名称';
                                }
                                return null;
                              },
                            ),
                            _FieldTile(
                              label: '日期',
                              value: _dateText,
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickDate,
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: '每次粒数',
                        trailing: Text(
                          '共 $total 粒',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            _DoseField(
                              label: '早餐',
                              controller: _breakfast,
                              onChanged: () => setState(() {}),
                            ),
                            _DoseField(
                              label: '午餐',
                              controller: _lunch,
                              onChanged: () => setState(() {}),
                            ),
                            _DoseField(
                              label: '晚餐',
                              controller: _dinner,
                              onChanged: () => setState(() {}),
                            ),
                            Text(
                              '粒数为 0 表示该餐不服用；保存后可在列表里按餐打卡。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.isEdit)
                        SectionCard(
                          title: '是否已服',
                          child: Column(
                            spacing: 4,
                            children: <Widget>[
                              _TakenSwitch(
                                label: '早餐',
                                dose: int.tryParse(_breakfast.text.trim()) ?? 0,
                                value: _takenBreakfast,
                                onChanged: (bool value) =>
                                    setState(() => _takenBreakfast = value),
                              ),
                              _TakenSwitch(
                                label: '午餐',
                                dose: int.tryParse(_lunch.text.trim()) ?? 0,
                                value: _takenLunch,
                                onChanged: (bool value) =>
                                    setState(() => _takenLunch = value),
                              ),
                              _TakenSwitch(
                                label: '晚餐',
                                dose: int.tryParse(_dinner.text.trim()) ?? 0,
                                value: _takenDinner,
                                onChanged: (bool value) =>
                                    setState(() => _takenDinner = value),
                              ),
                            ],
                          ),
                        ),
                      SectionCard(
                        title: '备注',
                        child: TextFormField(
                          controller: _note,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: '可选，例如医嘱、服用方式',
                          ),
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
                      Text(
                        '保存需要联网，成功后列表、今日统计与 7 日依从率会立即刷新。',
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

/// 单餐已服开关：粒数为 0 时禁用（该餐不服用）。
class _TakenSwitch extends StatelessWidget {
  const _TakenSwitch({
    required this.label,
    required this.dose,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int dose;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        dose == 0 ? '该餐不服用' : '$dose 粒',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      value: dose > 0 && value,
      onChanged: dose == 0 ? null : onChanged,
    );
  }
}

/// 单餐粒数输入：整数字。
class _DoseField extends StatelessWidget {
  const _DoseField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;

  /// 输入变化时通知父级重算「共 N 粒」。
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: <Widget>[
        SizedBox(
          width: 48,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.end,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: '粒',
            ),
            validator: (String? value) {
              final int? parsed = int.tryParse((value ?? '').trim());
              if (parsed == null || parsed < 0) {
                return '请填不小于 0 的整数';
              }
              return null;
            },
          ),
        ),
      ],
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
