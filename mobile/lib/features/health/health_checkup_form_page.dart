import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 体检指标记录录入 / 编辑。
///
/// 字段与网页端 `/health/checkup` 记录表一致：
/// 检查日期、指标项、数值、单位、参考下限/上限、参考范围、状态、备注。
///
/// - 新增：`POST /health/checkup`；编辑：`PUT /health/checkup/{id}`；
/// - 删除：`DELETE /health/checkup/{id}`（仅编辑态可见，二次确认写明影响）。
///
/// 空值口径：
/// - 数值与参考上下限留空一律提交 null，不写 0；
/// - 单位、参考范围原样提交后端原始值，客户端不改写语义；
/// - 状态选「自动判断」时不传 result，由后端按参考上下限推导（normal/high/low）。
class HealthCheckupFormPage extends StatefulWidget {
  const HealthCheckupFormPage({super.key, this.recordId, this.initial});

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，打开即预填；为空时按 [recordId] 拉取。
  final CheckupRecord? initial;

  @override
  State<HealthCheckupFormPage> createState() => _HealthCheckupFormPageState();
}

class _HealthCheckupFormPageState extends State<HealthCheckupFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _itemName = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _unit = TextEditingController();
  final TextEditingController _refLow = TextEditingController();
  final TextEditingController _refHigh = TextEditingController();
  final TextEditingController _referenceRange = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();

  /// 状态取值：空串 = 自动判断，其余为后端枚举 normal / high / low。
  String _result = '';

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final CheckupRecord? initial = widget.initial;
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
    _itemName.dispose();
    _value.dispose();
    _unit.dispose();
    _refLow.dispose();
    _refHigh.dispose();
    _referenceRange.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用一条记录预填：未采集字段留空，不用 0 兜底。
  void _apply(CheckupRecord record) {
    _date = DateTime.tryParse(record.checkDate) ?? DateTime.now();
    _itemName.text = record.itemName;
    _value.text = _plain(record.value);
    _unit.text = record.unit ?? '';
    _refLow.text = _plain(record.refLow);
    _refHigh.text = _plain(record.refHigh);
    _referenceRange.text = record.referenceRange ?? '';
    _note.text = record.note ?? '';
    _result = const <String>{'normal', 'high', 'low'}.contains(record.result)
        ? record.result!
        : '';
  }

  /// `5.60` → `5.6`，避免预填出现多余小数位。
  String _plain(double? value) {
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
            '/health/checkup/${widget.recordId}',
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '体检记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(CheckupRecord.fromJson(json));
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

  /// `yyyy-MM-dd`（后端 `check_date` 口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择检查日期。
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
      setState(() => _error = '当前无网络：体检记录需要联网保存，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'check_date': _dateText,
      'item_name': _itemName.text.trim(),
      'value': _optionalDouble(_value),
      'unit': _optionalText(_unit),
      'ref_low': _optionalDouble(_refLow),
      'ref_high': _optionalDouble(_refHigh),
      'reference_range': _optionalText(_referenceRange),
      'result': _result.isEmpty ? null : _result,
      'note': _optionalText(_note),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/checkup/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/checkup',
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
                ? '已更新 ${_itemName.text.trim()} 的体检记录'
                : '已保存 ${_itemName.text.trim()} 的体检记录',
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

  /// 删除：二次确认写明异常计数与趋势的影响。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除该条体检记录？'),
          content: Text(
            '将删除 $_dateText「${_itemName.text.trim()}」的记录。\n'
            '删除后该指标的异常 / 未判定计数、历史趋势与体检概览会同步回退，且无法恢复。',
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
        '/health/checkup/${widget.recordId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条体检记录')));
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
      title: _editing ? '编辑体检记录' : '新增体检记录',
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
                      ? '保存后该指标的异常计数、历史趋势与概览会同步更新。'
                      : '数值、参考上下限留空按「未采集」提交，不会写入 0。',
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
                        title: _editing ? '修改体检记录' : '体检指标',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            _FieldTile(
                              label: '检查日期',
                              value: _dateText,
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickDate,
                            ),
                            TextFormField(
                              controller: _itemName,
                              autofocus: !_editing,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '指标项（必填）',
                                hintText: '例如 空腹血糖',
                              ),
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return '请填写指标项';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _value,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '数值（可选）',
                                hintText: '例如 5.6',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '数值'),
                            ),
                            TextFormField(
                              controller: _unit,
                              decoration: const InputDecoration(
                                labelText: '单位（可选）',
                                hintText: '例如 mmol/L',
                              ),
                            ),
                            TextFormField(
                              controller: _refLow,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '参考下限（可选）',
                                hintText: '例如 3.9',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '参考下限'),
                            ),
                            TextFormField(
                              controller: _refHigh,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '参考上限（可选）',
                                hintText: '例如 6.1',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '参考上限'),
                            ),
                            TextFormField(
                              controller: _referenceRange,
                              decoration: const InputDecoration(
                                labelText: '参考范围（可选，原样展示）',
                                hintText: '留空则按上下限自动生成，例如 3.9~6.1',
                              ),
                            ),
                            AppSelectField<String>(
                              label: '状态',
                              value: _result,
                              options: const <AppSelectOption<String>>[
                                AppSelectOption<String>(
                                  value: '',
                                  label: '自动判断（按参考范围）',
                                ),
                                AppSelectOption<String>(
                                  value: 'normal',
                                  label: '正常',
                                ),
                                AppSelectOption<String>(
                                  value: 'high',
                                  label: '偏高',
                                ),
                                AppSelectOption<String>(
                                  value: 'low',
                                  label: '偏低',
                                ),
                              ],
                              onChanged: (String value) =>
                                  setState(() => _result = value),
                            ),
                            TextFormField(
                              controller: _note,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: '备注（可选）',
                                hintText: '例如 复查确认',
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

  /// 可空小数校验：留空合法；填写必须是合法数字（0 视为未采集，请留空）。
  String? _validateDouble(String? value, String label) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return '$label 请填数字';
    }
    if (parsed < 0) {
      return '$label 不能为负；未采集请留空';
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
