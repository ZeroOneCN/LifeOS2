import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 饮食记录录入 / 编辑：日期 + 餐次 + 食物名 + 重量（必填），热量与三大营养素可选。
///
/// 与网页端 `/health/fitness?tab=diet` 口径一致：
/// - 新增：`POST /health/diet`，底部整行「保存」；日期默认今天，
///   餐次按当前时间推断（11 点前早餐、15 点前午餐、21 点前晚餐，其余加餐）。
/// - 编辑：`PUT /health/diet/{id}`，底部「左保存、右删除」，删除二次确认；
///   重量与网页端一致不可修改（避免改了克数而热量不重算的脏数据）。
/// - 热量 / 营养素留空提交 null，由后端 `DietCreate.auto_nutrition`
///   按食物名与克数补算，客户端不自行计算，也不把「未填写」写成 0；
///   仅营养素留空而热量有值时后端不会补算，列表中显示「—」。
class HealthDietFormPage extends StatefulWidget {
  const HealthDietFormPage({super.key, this.recordId, this.initial});

  /// 编辑模式的记录 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照，用于打开即预填；为空时按 [recordId] 拉取。
  final DietRecord? initial;

  @override
  State<HealthDietFormPage> createState() => _HealthDietFormPageState();
}

class _HealthDietFormPageState extends State<HealthDietFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _foodName = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _calories = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();
  String _meal = '';

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final DietRecord? initial = widget.initial;
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
    } else {
      _meal = _inferredMeal();
    }
  }

  @override
  void dispose() {
    _foodName.dispose();
    _weight.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 按当前时间推断默认餐次：11 点前早餐、15 点前午餐、21 点前晚餐，其余加餐。
  static String _inferredMeal() {
    final int hour = DateTime.now().hour;
    if (hour < 11) {
      return 'breakfast';
    }
    if (hour < 15) {
      return 'lunch';
    }
    if (hour < 21) {
      return 'dinner';
    }
    return 'snack';
  }

  /// 用一条记录预填表单；餐次保留后端原值，未知值由下拉补一个同名选项。
  void _apply(DietRecord record) {
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _meal = record.mealType;
    _foodName.text = record.foodName;
    _weight.text = formatCompact(record.weightG);
    _calories.text = record.calories == null
        ? ''
        : formatCompact(record.calories);
    _protein.text = record.protein == null ? '' : formatCompact(record.protein);
    _carbs.text = record.carbs == null ? '' : formatCompact(record.carbs);
    _fat.text = record.fat == null ? '' : formatCompact(record.fat);
    _note.text = record.note ?? '';
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
            '/health/diet/${widget.recordId}',
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '饮食记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(DietRecord.fromJson(json));
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

  /// 选择饮食日期。
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
    final String text = controller.text.replaceAll(',', '').trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 提交：新增走 POST、编辑走 PUT；失败保留输入便于修正。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_meal.isEmpty) {
      setState(() => _error = '请选择餐次');
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：饮食记录需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'meal_type': _meal,
      'food_name': _foodName.text.trim(),
      'weight_g': double.parse(_weight.text.replaceAll(',', '').trim()),
      // 显式回传 null：热量留空时由后端补算，营养素留空保持空值（列表显示「—」）。
      'calories': _optional(_calories),
      'protein': _optional(_protein),
      'carbs': _optional(_carbs),
      'fat': _optional(_fat),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/diet/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/diet',
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
                ? '已保存 $_dateText 的${mealTypeLabel(_meal)}记录'
                : '已添加 ${mealTypeLabel(_meal)} · ${_foodName.text.trim()}',
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

  /// 删除：二次确认说明无法恢复，成功后返回列表刷新今日与每日小计。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该条饮食记录？'),
          content: Text(
            '将删除 $_dateText ${mealTypeLabel(_meal)}的「${_foodName.text.trim()}」。\n'
            '删除后今日摄入与当天小计会同步回退，且无法恢复。',
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
      await scope.apiClient.delete<dynamic>('/health/diet/${widget.recordId}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条饮食记录')));
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
    final bool busy = _saving || _deleting;
    return DetailPageScaffold(
      title: _editing ? '编辑饮食记录' : '新增饮食记录',
      bottomBar: _editing
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
          : AppPrimaryButton(
              label: '保存',
              loading: _saving,
              onPressed: busy ? null : _save,
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
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      SectionCard(
                        title: _editing ? '修改饮食记录' : '饮食信息',
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
                            AppSelectField<String>(
                              label: '餐次',
                              value: _meal,
                              options: <AppSelectOption<String>>[
                                for (final ({String value, String label}) item
                                    in kMealTypes)
                                  AppSelectOption<String>(
                                    value: item.value,
                                    label: item.label,
                                  ),
                                // 历史数据可能是四个选项外的餐次，原样保留避免编辑时丢失。
                                if (_meal.isNotEmpty &&
                                    !kMealTypes.any(
                                      (({String value, String label}) item) =>
                                          item.value == _meal,
                                    ))
                                  AppSelectOption<String>(
                                    value: _meal,
                                    label: mealTypeLabel(_meal),
                                  ),
                              ],
                              hint: '请选择餐次',
                              onChanged: (String value) =>
                                  setState(() => _meal = value),
                            ),
                            TextFormField(
                              controller: _foodName,
                              decoration: const InputDecoration(
                                labelText: '食物名称（必填）',
                                hintText: '如：鸡胸肉、米饭、苹果',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return '请输入食物名称';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _weight,
                              enabled: !_editing,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: '重量（必填）',
                                hintText: '例如 150',
                                suffixText: 'g',
                                helperText: _editing
                                    ? '编辑模式不可修改重量（与网页端一致）'
                                    : null,
                                helperMaxLines: 2,
                              ),
                              validator: (String? value) {
                                final double? parsed = double.tryParse(
                                  (value ?? '').replaceAll(',', '').trim(),
                                );
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的克数';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: '营养（可留空）',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _calories,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '热量',
                                hintText: '留空由后端自动补算',
                                suffixText: 'kcal',
                              ),
                              validator: (String? value) =>
                                  _validateNonNegative(value, '热量'),
                            ),
                            Row(
                              spacing: 12,
                              children: <Widget>[
                                Expanded(
                                  child: TextFormField(
                                    controller: _protein,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: '蛋白质',
                                      suffixText: 'g',
                                    ),
                                    validator: (String? value) =>
                                        _validateNonNegative(value, '蛋白质'),
                                  ),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _carbs,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: '碳水',
                                      suffixText: 'g',
                                    ),
                                    validator: (String? value) =>
                                        _validateNonNegative(value, '碳水'),
                                  ),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _fat,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: '脂肪',
                                      suffixText: 'g',
                                    ),
                                    validator: (String? value) =>
                                        _validateNonNegative(value, '脂肪'),
                                  ),
                                ),
                              ],
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
                            hintText: '可选，例如口味、份量、餐后感受',
                          ),
                        ),
                      ),
                      Text(
                        _editing
                            ? '热量与营养素可留空：热量清空后保存，后端会按食物名与克数重新补算；'
                                '仅营养素留空则保持空值，列表显示「—」。'
                            : '热量留空时后端会按食物名与克数自动补算（同时补全缺失营养素）；'
                                '客户端不自行计算，也不把留空写成 0。',
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

  /// 可选数值校验：留空合法；填写必须是不小于 0 的数字。
  String? _validateNonNegative(String? value, String label) {
    final String text = (value ?? '').replaceAll(',', '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      return '请输入不小于 0 的$label';
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
