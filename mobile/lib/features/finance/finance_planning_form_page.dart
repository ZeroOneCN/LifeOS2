import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增 / 编辑财务规划：日期 / 类型 / 标题 / 目标金额 / 已存金额 / 状态 / 备注。
///
/// 对应后端 `POST /finance/planning` 与 `PUT /finance/planning/{id}`（`PlanCreate`）。
class FinancePlanningFormPage extends StatefulWidget {
  const FinancePlanningFormPage({super.key, this.recordId, this.initial});

  /// 非空表示编辑模式。
  final int? recordId;
  final PlanItem? initial;

  bool get isEditing => recordId != null;

  @override
  State<FinancePlanningFormPage> createState() =>
      _FinancePlanningFormPageState();
}

class _FinancePlanningFormPageState extends State<FinancePlanningFormPage> {
  static const List<String> _planTypes = <String>['储蓄', '预算', '投资', '目标'];
  static const List<String> _statuses = <String>['active', 'done', 'abandoned'];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _date = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _targetAmount = TextEditingController();
  final TextEditingController _savedAmount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _planType = _planTypes.first;
  String _status = 'active';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final PlanItem? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
    } else if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRecord();
        }
      });
    }
    _date.text = _dateText(_selectedDate);
  }

  /// 用列表快照预填；空金额保持空白，不写 0。
  void _apply(PlanItem plan) {
    _selectedDate = DateTime.tryParse(plan.planDate) ?? DateTime.now();
    _planType = plan.planType.isEmpty ? _planTypes.first : plan.planType;
    _status = plan.status.isEmpty ? 'active' : plan.status;
    _title.text = plan.title;
    _targetAmount.text = _amountText(plan.targetAmount);
    _savedAmount.text = _amountText(plan.savedAmount);
    _note.text = plan.note ?? '';
  }

  /// 金额转输入框文本；null 保持空串。
  String _amountText(double? value) {
    if (value == null) {
      return '';
    }
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// 深链进入且无快照时按 id 拉取。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/finance/planning/${widget.recordId}'))
          .data;
      if (!mounted || json == null) {
        return;
      }
      setState(() {
        _apply(PlanItem.fromJson(json));
        _date.text = _dateText(_selectedDate);
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _title.dispose();
    _targetAmount.dispose();
    _savedAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd`（后端 `plan_date` 口径）。
  String _dateText(DateTime value) {
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDate = picked;
      _date.text = _dateText(picked);
    });
  }

  /// 保存：金额留空按未设置提交（不写 0），成功后返回列表刷新。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'plan_date': _date.text,
      'plan_type': _planType,
      'title': _title.text.trim(),
      'target_amount': _parseAmount(_targetAmount.text),
      'saved_amount': _parseAmount(_savedAmount.text),
      'status': _status,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (widget.isEditing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/planning/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/finance/planning',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(widget.isEditing ? '已更新财务规划' : '已新增财务规划')),
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

  /// 金额字符串转 double；留空返回 null（表示未设置，而不是 0）。
  double? _parseAmount(String raw) {
    final String text = raw.replaceAll(',', '').trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  /// 可空金额校验：留空通过，否则必须是不小于 0 的数字。
  String? _validateOptionalAmount(String? value) {
    final String text = (value ?? '').replaceAll(',', '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      return '请输入不小于 0 的金额';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: widget.isEditing ? '编辑财务规划' : '新增财务规划',
      bottomBar: SizedBox(
        width: double.infinity,
        child: AppPrimaryButton(
          label: '保存',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
      child: Form(
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
                  title: '规划信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      TextFormField(
                        controller: _title,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '标题',
                          hintText: '例如 旅行基金、年度储蓄',
                        ),
                        validator: (String? value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请填写规划标题';
                          }
                          return null;
                        },
                      ),
                      AppSelectField<String>(
                        label: '类型',
                        value: _planType,
                        options: <AppSelectOption<String>>[
                          for (final String type in _planTypes)
                            AppSelectOption<String>(value: type, label: type),
                          // 历史数据可能带自定义类型：保留原值，避免编辑时丢失语义。
                          if (!_planTypes.contains(_planType))
                            AppSelectOption<String>(
                              value: _planType,
                              label: _planType,
                            ),
                        ],
                        onChanged: (String value) =>
                            setState(() => _planType = value),
                      ),
                      AppSelectField<String>(
                        label: '状态',
                        value: _status,
                        options: <AppSelectOption<String>>[
                          for (final String status in _statuses)
                            AppSelectOption<String>(
                              value: status,
                              label: planStatusLabel(status),
                            ),
                        ],
                        onChanged: (String value) =>
                            setState(() => _status = value),
                      ),
                      TextFormField(
                        controller: _date,
                        readOnly: true,
                        onTap: _pickDate,
                        decoration: const InputDecoration(
                          labelText: '计划日期',
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                      TextFormField(
                        controller: _targetAmount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          labelText: '目标金额（可选）',
                          hintText: '0.00',
                          prefixText: '¥ ',
                        ),
                        validator: _validateOptionalAmount,
                      ),
                      TextFormField(
                        controller: _savedAmount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          labelText: '已存金额（可选）',
                          hintText: '0.00',
                          prefixText: '¥ ',
                        ),
                        validator: _validateOptionalAmount,
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
                      labelText: '备注（可选）',
                      hintText: '例如 每月固定存入 500 元',
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
}
