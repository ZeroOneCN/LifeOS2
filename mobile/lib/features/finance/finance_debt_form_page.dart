import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import 'finance_status_widgets.dart';

/// 债务本体录入 / 编辑：日期、名称、方向、对方、金额、途径、利率、到期日、备注。
///
/// 字段与网页端 `/finance/debts` 的「新增借款 / 编辑借款」弹窗一致。
///
/// 关键约束：
/// - **不写 `remaining` 与 `status`**。这两个字段由还款/收款接口与后端记录维护，
///   客户端不自行推算落库；保存后回到列表重拉，展示后端返回的剩余与状态。
/// - 新增走 `POST /finance/debts`，底部整行「保存」；
///   编辑走 `PUT /finance/debts/{id}`，底部「左保存、右删除」，删除二次确认。
/// - 留空的可选字段传 null（或 0 表示不计息），不把空字符串落库。
class FinanceDebtFormPage extends StatefulWidget {
  const FinanceDebtFormPage({super.key, this.debtId, this.initial});

  /// 编辑模式的债务 id；为空即新增。
  final int? debtId;

  /// 详情/列表带进来的快照，用于打开即预填；为空时按 [debtId] 拉取。
  final DebtItem? initial;

  @override
  State<FinanceDebtFormPage> createState() => _FinanceDebtFormPageState();
}

class _FinanceDebtFormPageState extends State<FinanceDebtFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _counterparty = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _interestRate = TextEditingController();
  final TextEditingController _interestTotal = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  String _direction = 'borrow';
  String _channel = '现金';

  DebtItem? _record;
  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.debtId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final DebtItem? initial = widget.initial;
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
    _name.dispose();
    _counterparty.dispose();
    _amount.dispose();
    _interestRate.dispose();
    _interestTotal.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用一条债务预填表单（只回填本页维护的字段）。
  void _apply(DebtItem item) {
    _record = item;
    _date = DateTime.tryParse(item.debtDate) ?? DateTime.now();
    _dueDate = item.dueDate == null ? null : DateTime.tryParse(item.dueDate!);
    _name.text = item.name;
    _counterparty.text = item.counterparty ?? '';
    _amount.text = _plain(item.amount);
    _interestRate.text = item.interestRate == null
        ? ''
        : _plain(item.interestRate!);
    _interestTotal.text = _plain(item.interestTotal);
    _note.text = item.note ?? '';
    _direction = item.isLend ? 'lend' : 'borrow';
    _channel = item.channel == null || item.channel!.isEmpty
        ? '现金'
        : item.channel!;
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
            '/finance/debts/${widget.debtId}',
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '债务记录返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(DebtItem.fromJson(json));
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

  /// `yyyy-MM-dd`（后端日期字段口径）。
  String _dateText(DateTime value) {
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  /// 选择借款/出借日期。
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _date = picked);
  }

  /// 选择到期日（可空，第二行提供清除入口）。
  Future<void> _pickDueDate() async {
    final DateTime base = _dueDate ?? _date.add(const Duration(days: 30));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _dueDate = picked);
  }

  /// 可选数值字段：留空返回 null，非法输入交给校验器拦截。
  double? _optional(TextEditingController controller) {
    final String text = controller.text.replaceAll(',', '').trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 提交：新增走 POST、编辑走 PUT；不提交 `remaining` / `status`。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：债务录入需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final double amount = double.parse(_amount.text.replaceAll(',', '').trim());
    final Map<String, dynamic> payload = <String, dynamic>{
      'debt_date': _dateText(_date),
      'name': _name.text.trim(),
      'direction': _direction,
      'counterparty': _counterparty.text.trim().isEmpty
          ? null
          : _counterparty.text.trim(),
      'amount': amount,
      'interest_rate': _optional(_interestRate),
      // 「应付利息总额」留空按 0（不计息）提交，与网页端一致。
      'interest_total': _optional(_interestTotal) ?? 0,
      'channel': _channel,
      'due_date': _dueDate == null ? null : _dateText(_dueDate!),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/debts/${widget.debtId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/finance/debts',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(_editing ? 'saved' : true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? '已保存债务「${_name.text.trim()}」'
                : '已添加${_direction == 'lend' ? '借出' : '借入'}'
                      '「${_name.text.trim()}」${formatMoney(amount)}',
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

  /// 删除：二次确认说明还款明细与汇总会一起消失，成功后返回列表刷新。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该笔债务？'),
          content: Text(
            '将删除「${_name.text.trim()}」${_dateText(_date)} 的债务记录。\n'
            '该债务的还款/收款明细将不再展示，借入借出合计与未结清余额会同步回退，'
            '且无法恢复。',
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
      await scope.apiClient.delete<dynamic>('/finance/debts/${widget.debtId}');
      if (!mounted) {
        return;
      }
      navigator.pop('deleted');
      messenger.showSnackBar(const SnackBar(content: Text('已删除该笔债务')));
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
    final DebtItem? record = _record;
    return DetailPageScaffold(
      title: _editing ? '编辑债务' : '新增债务',
      bottomBar: _editing
          ? AppActionRow(
              first: AppPrimaryButton(
                label: '保存',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _loading || _saving || _deleting ? null : _save,
              ),
              second: AppDangerButton(
                label: '删除',
                loading: _deleting,
                onPressed: _loading || _saving || _deleting ? null : _delete,
              ),
            )
          : AppPrimaryButton(
              label: '保存',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: _loading || _saving ? null : _save,
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
                      if (_editing && record != null)
                        SectionCard(
                          title: '还款状态',
                          trailing: StatusChip(
                            label: debtStatusLabel(record.status),
                            tone: record.status == 'settled'
                                ? StatusTone.success
                                : StatusTone.info,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 4,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      '本金',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    formatMoney(record.amount),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      '剩余金额',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    formatMoney(record.outstanding),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '剩余金额与状态由还款/收款记录决定；这里只改债务本身，'
                                '保存后自动更新。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      SectionCard(
                        title: _editing ? '修改债务信息' : '债务信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            _DateTile(
                              label: '日期',
                              value: _dateText(_date),
                              onTap: _pickDate,
                            ),
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '债务名称（必填）',
                                hintText: '例如 朋友借款 / 房贷',
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '请填写债务名称';
                                }
                                return null;
                              },
                            ),
                            AppSelectField<String>(
                              label: '方向',
                              value: _direction,
                              options: const <AppSelectOption<String>>[
                                AppSelectOption<String>(
                                  value: 'borrow',
                                  label: '借入（应付）',
                                ),
                                AppSelectOption<String>(
                                  value: 'lend',
                                  label: '借出（应收）',
                                ),
                              ],
                              onChanged: (String value) =>
                                  setState(() => _direction = value),
                            ),
                            TextFormField(
                              controller: _counterparty,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '对方（可选）',
                                hintText: '债权人 / 借款人',
                              ),
                            ),
                            TextFormField(
                              controller: _amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: '金额（本金必填）',
                                hintText: '0.00',
                                prefixText: '¥ ',
                              ),
                              validator: (String? value) {
                                final double? parsed = double.tryParse(
                                  (value ?? '').replaceAll(',', '').trim(),
                                );
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的金额';
                                }
                                return null;
                              },
                            ),
                            AppSelectField<String>(
                              label: '途径',
                              value: _channel,
                              options: const <AppSelectOption<String>>[
                                AppSelectOption<String>(
                                  value: '现金',
                                  label: '现金',
                                ),
                                AppSelectOption<String>(
                                  value: '银行转账',
                                  label: '银行转账',
                                ),
                                AppSelectOption<String>(
                                  value: '微信',
                                  label: '微信',
                                ),
                                AppSelectOption<String>(
                                  value: '支付宝',
                                  label: '支付宝',
                                ),
                                AppSelectOption<String>(
                                  value: '其他',
                                  label: '其他',
                                ),
                              ],
                              onChanged: (String value) =>
                                  setState(() => _channel = value),
                            ),
                            _DateTile(
                              label: '到期日（可选）',
                              value: _dueDate == null
                                  ? '未设置'
                                  : _dateText(_dueDate!),
                              onTap: _pickDueDate,
                              onClear: _dueDate == null
                                  ? null
                                  : () => setState(() => _dueDate = null),
                            ),
                            TextFormField(
                              controller: _interestRate,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '年利率（可选）',
                                hintText: '例如 3.5',
                                suffixText: '%',
                              ),
                              validator: (String? value) =>
                                  _validateNonNegative(value, '年利率'),
                            ),
                            TextFormField(
                              controller: _interestTotal,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '应付利息总额（可选）',
                                hintText: '留空按 0（不计息）',
                                suffixText: '元',
                              ),
                              validator: (String? value) =>
                                  _validateNonNegative(value, '利息总额'),
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
                            hintText: '可选，例如借款用途、约定还款方式',
                          ),
                        ),
                      ),
                      Text(
                        _editing
                            ? '剩余金额与状态由还款记录决定，不在这里修改。'
                            : '保存后借入借出合计与未结清余额会同步更新；剩余金额默认等于本金。',
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

/// 把金额转成不带多余尾零的输入文本（例如 1200.00 → 1200）。
String _plain(double value) {
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 日期只读行：点按弹日历；[onClear] 非空时右侧提供清除按钮。
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : IconButton(
                  tooltip: '清除日期',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
        ),
        child: Text(value),
      ),
    );
  }
}
