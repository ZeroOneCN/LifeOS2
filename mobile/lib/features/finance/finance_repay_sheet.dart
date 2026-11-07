import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_buttons.dart';

/// 债务还款 / 收款的底部弹层。
///
/// 金额语义（与网贷相反，文案必须写清）：
/// - `amount` = 本次清账金额（含优惠部分），默认填剩余未还；
/// - `discount` = 其中优惠（减免/抵扣），实付 = amount - discount；
/// - 后端剩余 = 剩余 - amount，归零即结清。
///
/// 编辑模式复用同一弹层：提交走 `PATCH /finance/debts/{id}/payments/{pid}`，
/// 并支持二次确认后删除该还款记录（后端会回滚剩余与状态）。
class DebtRepaySheet extends StatefulWidget {
  const DebtRepaySheet({super.key, required this.debt, this.payment});

  final DebtItem debt;

  /// 传入表示编辑已有还款记录；为空表示新增。
  final DebtPayment? payment;

  @override
  State<DebtRepaySheet> createState() => _DebtRepaySheetState();
}

class _DebtRepaySheetState extends State<DebtRepaySheet> {
  late final TextEditingController _amount;
  late final TextEditingController _discount;
  late final TextEditingController _note;
  late DateTime _date;

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _isEdit => widget.payment != null;

  /// 可用额度：编辑时把这条记录已占用的清账额加回剩余，避免误报超限。
  double get _limit =>
      widget.debt.outstanding + (_isEdit ? widget.payment!.amount : 0);

  /// 操作文案：借入是还款，借出是收款。
  String get _action => widget.debt.isLend ? '收款' : '还款';

  @override
  void initState() {
    super.initState();
    final DebtPayment? payment = widget.payment;
    final double remaining = widget.debt.outstanding;
    _amount = TextEditingController(
      text: payment != null
          ? _plain(payment.amount)
          : (remaining > 0 ? remaining.toStringAsFixed(2) : ''),
    );
    _discount = TextEditingController(
      text: payment != null && payment.discount > 0
          ? _plain(payment.discount)
          : '',
    );
    _note = TextEditingController(text: payment?.note ?? '');
    final DateTime? parsed =
        payment == null ? null : DateTime.tryParse(payment.repayDate);
    _date = parsed ?? DateTime.now();
    for (final TextEditingController controller in <TextEditingController>[
      _amount,
      _discount,
    ]) {
      controller.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _discount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _recalculate() {
    if (mounted) {
      setState(() => _error = null);
    }
  }

  /// 去掉无意义的小数尾巴：10.00 → 10，10.50 → 10.5。
  static String _plain(double value) {
    final String text = value.toStringAsFixed(2);
    if (text.endsWith('.00')) {
      return text.substring(0, text.length - 3);
    }
    return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
  }

  static double? _parse(TextEditingController controller) {
    final String text = controller.text.trim().replaceAll(',', '');
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 当前输入的清账额、优惠、实付与剩余（无效输入按 0 处理，仅用于预览）。
  ({double amount, double discount, double actual, double remaining})
      get _preview {
    final double amount = _parse(_amount) ?? 0;
    final double discount = _parse(_discount) ?? 0;
    final double actual = amount - discount < 0 ? 0 : amount - discount;
    final double remaining = widget.debt.outstanding - amount;
    return (
      amount: amount,
      discount: discount,
      actual: actual,
      remaining: remaining < 0 ? 0 : remaining,
    );
  }

  /// 提交前校验：与网页端一致（金额>0、优惠≥0、优惠≤清账额、清账额≤可用剩余）。
  String? _validate() {
    final double? amount = _parse(_amount);
    final double? discount = _parse(_discount);
    if (amount == null || amount <= 0) {
      return '本次清账金额必须大于 0';
    }
    final double dsc = discount ?? 0;
    if (dsc < 0) {
      return '优惠金额不能为负';
    }
    if (dsc > amount + 1e-6) {
      return '优惠金额不能大于清账金额';
    }
    if (amount > _limit + 1e-6) {
      return '清账金额不能超过剩余 ${formatMoney(_limit)}';
    }
    return null;
  }

  /// 在线提交：还款是资金操作，不进入离线队列；失败保留表单可重试。
  Future<void> _submit() async {
    final String? invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final double amount = _parse(_amount)!;
    final double discount = _parse(_discount) ?? 0;
    final String dateText = _dateText(_date);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'repay_date': dateText,
        'amount': double.parse(amount.toStringAsFixed(2)),
        'discount': double.parse(discount.toStringAsFixed(2)),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      };
      final String path = _isEdit
          ? '/finance/debts/${widget.debt.id}/payments/${widget.payment!.id}'
          : '/finance/debts/${widget.debt.id}/repay';
      if (_isEdit) {
        await scope.apiClient.patch<Map<String, dynamic>>(path, data: payload);
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(path, data: payload);
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? '还款记录已更新' : '$_action记录已保存')),
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

  /// 删除还款记录：二次确认后在线删除，后端会回滚剩余金额与状态。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除还款记录？'),
          content: Text(
            '将删除 ${widget.payment!.repayDate} 的$_action记录'
            '（清账 ${formatMoney(widget.payment!.amount)}），'
            '并从债务剩余中回滚。删除后无法恢复。',
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
    setState(() => _deleting = true);
    try {
      await scope.apiClient.delete<dynamic>(
        '/finance/debts/${widget.debt.id}/payments/${widget.payment!.id}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('还款记录已删除')));
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
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final ({double amount, double discount, double actual, double remaining})
        preview = _preview;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                Text(
                  _isEdit ? '修改$_action记录' : '$_action · ${widget.debt.name}',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '债务剩余 ${formatMoney(widget.debt.outstanding)} · '
                  '${widget.debt.name}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                _DateField(
                  label: '$_action日期',
                  value: _dateText(_date),
                  onTap: _pickDate,
                ),
                _MoneyField(
                  controller: _amount,
                  label: '本次清账（含优惠）',
                  helper: '默认填剩余应还，可改小做部分$_action',
                ),
                _MoneyField(
                  controller: _discount,
                  label: '其中优惠',
                  helper: '减免/抵扣券金额，实付 = 清账 - 优惠',
                ),
                TextField(
                  controller: _note,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    counterText: '',
                  ),
                ),
                _PreviewBox(
                  title: '本次$_action预览',
                  lines: <String>[
                    '实付 ${formatMoney(preview.actual)}'
                        ' + 优惠 ${formatMoney(preview.discount)}'
                        ' = 清账 ${formatMoney(preview.amount)}',
                    '清账后剩余 ${formatMoney(preview.remaining)}',
                  ],
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                if (_isEdit)
                  AppActionRow(
                    first: AppPrimaryButton(
                      label: '保存修改',
                      icon: Icons.save_outlined,
                      loading: _saving,
                      onPressed: _deleting ? null : _submit,
                    ),
                    second: AppDangerButton(
                      label: '删除',
                      loading: _deleting,
                      onPressed: _saving ? null : _delete,
                    ),
                  )
                else
                  AppPrimaryButton(
                    label: '确认$_action',
                    icon: Icons.payments_outlined,
                    loading: _saving,
                    onPressed: _deleting ? null : _submit,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 选择还款/收款日期（允许补录过去日期）。
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: '选择$_action日期',
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }
}

/// 网贷账单还款弹层。
///
/// 金额语义（与债务相反，文案必须写清）：
/// - `amount` = 本次实付（不含优惠）；
/// - `discount` = 优惠（券/抵扣）；
/// - 后端清账 = amount + discount，`paid_amount = Σ(amount + discount)`；
/// - 状态由后端重算：待还 / 部分已还 / 已结清。
///
/// 编辑模式提交 `PUT /finance/repayments/{id}`，删除走二次确认后 DELETE。
class LoanRepaySheet extends StatefulWidget {
  const LoanRepaySheet({super.key, required this.bill, this.repayment});

  final BillItem bill;

  /// 传入表示编辑已有还款记录；为空表示新增。
  final BillRepayment? repayment;

  @override
  State<LoanRepaySheet> createState() => _LoanRepaySheetState();
}

class _LoanRepaySheetState extends State<LoanRepaySheet> {
  late final TextEditingController _amount;
  late final TextEditingController _discount;
  late final TextEditingController _method;
  late final TextEditingController _note;
  late DateTime _date;

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _isEdit => widget.repayment != null;

  /// 可用清账额度：编辑时把旧记录的实付 + 优惠加回剩余。
  double get _limit {
    final BillRepayment? repayment = widget.repayment;
    return widget.bill.remaining +
        (repayment == null ? 0 : repayment.amount + repayment.discount);
  }

  @override
  void initState() {
    super.initState();
    final BillRepayment? repayment = widget.repayment;
    _amount = TextEditingController(
      text: repayment != null
          ? _plain(repayment.amount)
          : (widget.bill.remaining > 0
              ? widget.bill.remaining.toStringAsFixed(2)
              : ''),
    );
    _discount = TextEditingController(
      text: repayment != null && repayment.discount > 0
          ? _plain(repayment.discount)
          : '',
    );
    _method = TextEditingController(text: repayment?.method ?? '');
    _note = TextEditingController(text: repayment?.note ?? '');
    final DateTime? parsed =
        repayment == null ? null : DateTime.tryParse(repayment.repayDate);
    _date = parsed ?? DateTime.now();
    for (final TextEditingController controller in <TextEditingController>[
      _amount,
      _discount,
    ]) {
      controller.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _discount.dispose();
    _method.dispose();
    _note.dispose();
    super.dispose();
  }

  void _recalculate() {
    if (mounted) {
      setState(() => _error = null);
    }
  }

  /// 去掉无意义的小数尾巴：10.00 → 10，10.50 → 10.5。
  static String _plain(double value) {
    final String text = value.toStringAsFixed(2);
    if (text.endsWith('.00')) {
      return text.substring(0, text.length - 3);
    }
    return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
  }

  static double? _parse(TextEditingController controller) {
    final String text = controller.text.trim().replaceAll(',', '');
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 当前输入的实付、优惠、清账额与清账后剩余（仅用于预览）。
  ({double actual, double discount, double applied, double remaining})
      get _preview {
    final double actual = _parse(_amount) ?? 0;
    final double discount = _parse(_discount) ?? 0;
    final double applied = actual + discount;
    final double remaining = widget.bill.remaining - applied;
    return (
      actual: actual,
      discount: discount,
      applied: applied,
      remaining: remaining < 0 ? 0 : remaining,
    );
  }

  /// 提交前校验：实付>0、优惠≥0、实付+优惠≤可用剩余。
  String? _validate() {
    final double? actual = _parse(_amount);
    if (actual == null || actual <= 0) {
      return '实付金额必须大于 0';
    }
    final double discount = _parse(_discount) ?? 0;
    if (discount < 0) {
      return '优惠金额不能为负';
    }
    if (actual + discount > _limit + 1e-2) {
      return '实付 + 优惠不能超过剩余 ${formatMoney(_limit)}';
    }
    return null;
  }

  /// 在线提交：资金操作不进入离线队列；失败保留表单可重试。
  Future<void> _submit() async {
    final String? invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final double actual = _parse(_amount)!;
    final double discount = _parse(_discount) ?? 0;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'bill_id': widget.bill.id,
        'repay_date': _dateText(_date),
        'amount': double.parse(actual.toStringAsFixed(2)),
        'discount': double.parse(discount.toStringAsFixed(2)),
        'method': _method.text.trim().isEmpty ? null : _method.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      };
      if (_isEdit) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/repayments/${widget.repayment!.id}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/finance/repayments',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_isEdit ? '还款记录已更新' : '还款记录已保存')),
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

  /// 删除还款记录：二次确认后在线删除，后端会重算已还与账单状态。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除还款记录？'),
          content: Text(
            '将删除 ${widget.repayment!.repayDate} 的还款记录'
            '（实付 ${formatMoney(widget.repayment!.amount)}，'
            '优惠 ${formatMoney(widget.repayment!.discount)}），'
            '并重算账单已还与状态。删除后无法恢复。',
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
    setState(() => _deleting = true);
    try {
      await scope.apiClient.delete<dynamic>(
        '/finance/repayments/${widget.repayment!.id}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('还款记录已删除')));
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
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final ({double actual, double discount, double applied, double remaining})
        preview = _preview;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                Text(
                  _isEdit ? '修改还款记录' : '还款 · ${widget.bill.billMonth}',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '账单应还 ${formatMoney(widget.bill.amount)} · '
                  '已还 ${formatMoney(widget.bill.paidAmount)} · '
                  '剩余 ${formatMoney(widget.bill.remaining)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                _DateField(
                  label: '还款日期',
                  value: _dateText(_date),
                  onTap: _pickDate,
                ),
                _MoneyField(
                  controller: _amount,
                  label: '本次实付（优惠另填）',
                  helper: '默认填剩余应还，可改小做部分还款',
                ),
                _MoneyField(
                  controller: _discount,
                  label: '优惠（券/抵扣）',
                  helper: '清账 = 实付 + 优惠，优惠不会额外多还',
                ),
                TextField(
                  controller: _method,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: '还款方式',
                    hintText: '如：银行卡、支付宝、微信',
                    counterText: '',
                  ),
                ),
                TextField(
                  controller: _note,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    counterText: '',
                  ),
                ),
                _PreviewBox(
                  title: '本次还款预览',
                  lines: <String>[
                    '实付 ${formatMoney(preview.actual)}'
                        ' + 优惠 ${formatMoney(preview.discount)}'
                        ' = 清账 ${formatMoney(preview.applied)}',
                    '清账后剩余 ${formatMoney(preview.remaining)}',
                  ],
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                if (_isEdit)
                  AppActionRow(
                    first: AppPrimaryButton(
                      label: '保存修改',
                      icon: Icons.save_outlined,
                      loading: _saving,
                      onPressed: _deleting ? null : _submit,
                    ),
                    second: AppDangerButton(
                      label: '删除',
                      loading: _deleting,
                      onPressed: _saving ? null : _delete,
                    ),
                  )
                else
                  AppPrimaryButton(
                    label: '确认还款',
                    icon: Icons.payments_outlined,
                    loading: _saving,
                    onPressed: _deleting ? null : _submit,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 选择还款日期（允许补录过去日期）。
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: '选择还款日期',
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }
}

/// `yyyy-MM-dd` 文本。
String _dateText(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

/// 只读日期字段：点按后走系统日期选择器。
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value),
      ),
    );
  }
}

/// 金额输入字段：数字键盘 + 两位小数提示。
class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        // 金额字段统一带 ¥，与账单/债务页的展示口径一致。
        prefixText: '¥ ',
        helperText: helper,
      ),
    );
  }
}

/// 预览块：展开「实付 + 优惠 = 清账」，并给出清账后剩余。
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final String line in lines)
            Text(
              line,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
