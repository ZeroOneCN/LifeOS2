import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增用药记录：日期 + 药品名 + 早/午/晚粒数 + 备注。
///
/// 走网页端同一接口 `POST /health/medication`，字段与网页端一致
/// （`record_date` / `medicine_name` / `dose_*` / `taken_*` / `note`）。
///
/// 为什么在线提交而不是离线队列：用药记录是「当天的服药计划」，
/// 新增后要立刻出现在列表与「今日待办」里；后端该接口没有幂等键，
/// 入队重试可能写出两条同日同药记录（直接影响依从率统计）。
/// 在线失败时用户还在表单前，可直接改数据重试；
/// 而**打卡**是对既有记录的 PUT 更新，天然幂等，继续走离线队列。
class HealthMedicationCreatePage extends StatefulWidget {
  const HealthMedicationCreatePage({super.key});

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
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _breakfast.dispose();
    _lunch.dispose();
    _dinner.dispose();
    _note.dispose();
    super.dispose();
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

  /// 提交：在线创建，成功后返回 `true` 让列表与健康中心刷新。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：新增用药需要联网，请恢复网络后重试');
      return;
    }
    final int breakfast = int.parse(_breakfast.text.trim());
    final int lunch = int.parse(_lunch.text.trim());
    final int dinner = int.parse(_dinner.text.trim());
    if (breakfast + lunch + dinner <= 0) {
      setState(() => _error = '早/午/晚至少有一餐粒数大于 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await scope.apiClient.post<Map<String, dynamic>>(
        '/health/medication',
        data: <String, dynamic>{
          'record_date': _dateText,
          'medicine_name': _name.text.trim(),
          'dose_breakfast': breakfast,
          'dose_lunch': lunch,
          'dose_dinner': dinner,
          'taken_breakfast': false,
          'taken_lunch': false,
          'taken_dinner': false,
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        },
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('已添加 ${_name.text.trim()}（$_dateText）')),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total =
        (int.tryParse(_breakfast.text.trim()) ?? 0) +
        (int.tryParse(_lunch.text.trim()) ?? 0) +
        (int.tryParse(_dinner.text.trim()) ?? 0);
    return DetailPageScaffold(
      title: '新增用药',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
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
                        autofocus: true,
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
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
                Text(
                  '新增需要联网，成功后列表与今日待办会立即刷新。',
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
