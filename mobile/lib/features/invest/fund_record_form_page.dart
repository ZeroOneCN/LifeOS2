import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/investment_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 资金记录新增 / 编辑页（对应网页端「记录资金」弹窗）。
///
/// 字段与后端 `FundCreate` 一致：`record_type` / `record_date` / `amount` / `note`。
/// 金额允许体验金亏损为负数（历史数据存在），入金与出金必须为正数。
class FundRecordFormPage extends StatefulWidget {
  const FundRecordFormPage({super.key, this.recordId, this.initial});

  /// 编辑时的记录 id；为空表示新增。
  final int? recordId;

  /// 编辑时的原始记录，用于回填与文案。
  final FundRecord? initial;

  @override
  State<FundRecordFormPage> createState() => _FundRecordFormPageState();
}

class _FundRecordFormPageState extends State<FundRecordFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _type = kFundTypes.first.value;
  late String _date;

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    final FundRecord? record = widget.initial;
    _date = _todayKey();
    if (record != null) {
      _type = record.recordType;
      _date = record.recordDate;
      _amount.text = _plain(record.amount);
      _note.text = record.note ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 今天（本地时区）的 `YYYY-MM-DD`，与后端日期字段格式一致。
  String _todayKey() {
    final DateTime now = DateTime.now();
    return '${now.year}-${_two(now.month)}-${_two(now.day)}';
  }

  /// 金额回填：去掉无意义的小数尾零，避免编辑后数值被四舍五入。
  String _plain(double value) {
    final String text = value.toStringAsFixed(2);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  /// 选择发生日期；默认停在当前选中日期。
  Future<void> _pickDate() async {
    final DateTime initial = DateTime.tryParse(_date) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _date = '${picked.year}-${_two(picked.month)}-${_two(picked.day)}';
    });
  }

  /// 提交：新增走 POST，编辑走 PUT；失败保留输入便于修正。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：资金记录需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_type': _type,
      'record_date': _date,
      'amount': double.parse(_amount.text.replaceAll(',', '').trim()),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/investment/funds/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/investment/funds',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? '已保存资金记录' : '已记录资金')),
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

  /// 删除：二次确认写明金额与统计影响。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该资金记录？'),
          content: Text(
            '将删除 ${_fundTypeLabel(_type)} '
            '${formatUsdSigned(double.tryParse(_amount.text.trim()) ?? 0)}。\n'
            '删除后累计入金、累计出金、体验金与净投入会同步回退，且无法恢复。',
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
      await scope.apiClient.delete<dynamic>(
        '/investment/funds/${widget.recordId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该资金记录')));
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
    final List<AppSelectOption<String>> typeOptions =
        <AppSelectOption<String>>[
          for (final ({String value, String label}) item in kFundTypes)
            AppSelectOption<String>(value: item.value, label: item.label),
          // 历史记录可能带有未知类型，保留原名避免下拉显示为空。
          if (!kFundTypes.any(
            (({String value, String label}) item) => item.value == _type,
          ))
            AppSelectOption<String>(value: _type, label: _type),
        ];

    return DetailPageScaffold(
      title: _editing ? '编辑资金记录' : '记录资金',
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
                  title: '资金信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      AppSelectField<String>(
                        label: '类型',
                        value: _type,
                        options: typeOptions,
                        hint: '请选择类型',
                        onChanged: (String value) =>
                            setState(() => _type = value),
                      ),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: '发生日期'),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: Text(_date)),
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextFormField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: '金额（必填）',
                          hintText: '如 1000',
                          prefixText: r'$ ',
                        ),
                        validator: _amountValidator,
                      ),
                      Text(
                        '入金 / 出金填正数；体验金亏损可填负数。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextFormField(
                        controller: _note,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: '可选，例如首次入金、出金提现',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 金额校验：必填、可解析、不为 0；入金 / 出金必须为正数。
  String? _amountValidator(String? value) {
    final String text = (value ?? '').replaceAll(',', '').trim();
    if (text.isEmpty) {
      return '请输入金额';
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return '请输入有效的金额';
    }
    if (parsed == 0) {
      return '金额不能为 0';
    }
    if (_type != 'experience' && parsed < 0) {
      return '入金 / 出金必须为正数';
    }
    return null;
  }
}

/// 资金类型中文名；未知类型原样返回。
String _fundTypeLabel(String value) {
  for (final ({String value, String label}) item in kFundTypes) {
    if (item.value == value) {
      return item.label;
    }
  }
  return value;
}

/// 两位补零。
String _two(int value) => value < 10 ? '0$value' : '$value';
