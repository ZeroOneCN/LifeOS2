import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 卡片管理支持的四种对象。
enum CardKind { phone, bank, carrier, bill }

/// URL 参数 → 卡片类型；未知值回退到手机号卡。
CardKind cardKindFromParam(String? value) {
  switch (value) {
    case 'bank':
      return CardKind.bank;
    case 'carrier':
      return CardKind.carrier;
    case 'bill':
      return CardKind.bill;
    default:
      return CardKind.phone;
  }
}

/// 卡片新增 / 编辑表单：手机号卡、银行卡、运营商、扣账账单。
///
/// 对应后端标准 CRUD：
/// - `/lifestyle/phone-cards`
/// - `/lifestyle/bank-cards`
/// - `/lifestyle/carriers`
/// - `/lifestyle/card-bills`
///
/// 余额、本月扣费这类派生值不在表单里改写，保存后由后端重新计算。
class CardFormPage extends StatefulWidget {
  const CardFormPage({
    super.key,
    required this.kind,
    this.id,
    this.phone,
    this.bank,
    this.carrier,
    this.bill,
  });

  final CardKind kind;

  /// 非空表示编辑。
  final int? id;
  final PhoneCard? phone;
  final BankCard? bank;
  final Carrier? carrier;
  final CardBill? bill;

  bool get isEditing => id != null;

  @override
  State<CardFormPage> createState() => _CardFormPageState();
}

class _CardFormPageState extends State<CardFormPage> {
  static const List<String> _operators = <String>[
    '中国移动',
    '中国联通',
    '中国电信',
    '虚拟运营商',
  ];
  final TextEditingController _phoneNumber = TextEditingController();
  final TextEditingController _operator = TextEditingController();
  final TextEditingController _region = TextEditingController();
  final TextEditingController _openingBalance = TextEditingController();
  final TextEditingController _monthlyFee = TextEditingController();
  final TextEditingController _billDay = TextEditingController();
  final TextEditingController _dataPlan = TextEditingController();
  final TextEditingController _callPlan = TextEditingController();
  final TextEditingController _smsPlan = TextEditingController();
  final TextEditingController _phoneNote = TextEditingController();
  String _chargeMode = 'monthly';
  String _billingType = 'monthly';
  bool _autoCharge = true;
  String _phoneStatus = 'active';
  String? _openDate;

  final TextEditingController _cardName = TextEditingController();
  final TextEditingController _cardHolder = TextEditingController();
  final TextEditingController _bank = TextEditingController();
  final TextEditingController _cardNumber = TextEditingController();
  final TextEditingController _cardBalance = TextEditingController();
  final TextEditingController _creditLimit = TextEditingController();
  final TextEditingController _billingDay = TextEditingController();
  final TextEditingController _dueDay = TextEditingController();
  final TextEditingController _bankNote = TextEditingController();
  String _cardCategory = 'debit';
  String _cardForm = 'physical';
  String _bankStatus = 'active';
  String? _expireDate;

  final TextEditingController _carrierName = TextEditingController();
  final TextEditingController _carrierWebsite = TextEditingController();
  final TextEditingController _carrierContact = TextEditingController();
  final TextEditingController _carrierNote = TextEditingController();

  String _billPhoneId = '';
  String _billMonth = '';
  final TextEditingController _billAmount = TextEditingController();
  String? _deductedDate;
  bool _billPaid = true;
  final TextEditingController _billNote = TextEditingController();
  List<PhoneCard> _phoneOptions = const <PhoneCard>[];

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    switch (widget.kind) {
      case CardKind.phone:
        final PhoneCard? phone = widget.phone;
        if (phone != null) {
          _phoneNumber.text = phone.phoneNumber;
          _operator.text = phone.operator;
          _region.text = phone.region ?? '';
          _openingBalance.text = _amountText(phone.openingBalance);
          _monthlyFee.text = _amountText(phone.monthlyFee);
          _billDay.text = phone.billDay == null ? '' : '${phone.billDay}';
          _dataPlan.text = phone.dataPlan ?? '';
          _callPlan.text = phone.callPlan ?? '';
          _smsPlan.text = phone.smsPlan ?? '';
          _openDate = phone.openDate;
          _chargeMode = phone.chargeMode;
          _billingType = phone.billingType;
          _autoCharge = phone.autoCharge;
          _phoneStatus = phone.status;
          _phoneNote.text = phone.note ?? '';
        }
        break;
      case CardKind.bank:
        final BankCard? card = widget.bank;
        if (card != null) {
          _cardName.text = card.cardName;
          _cardHolder.text = card.cardHolder ?? '';
          _bank.text = card.bank;
          _cardCategory = card.cardCategory;
          _cardForm = card.cardForm;
          _cardNumber.text = card.cardNumber ?? '';
          _cardBalance.text = _amountText(card.balance);
          _creditLimit.text = _amountText(card.creditLimit);
          _billingDay.text =
              card.billingDay == null ? '' : '${card.billingDay}';
          _dueDay.text = card.dueDay == null ? '' : '${card.dueDay}';
          _expireDate = card.expireDate;
          _bankStatus = card.status;
          _bankNote.text = card.note ?? '';
        }
        break;
      case CardKind.carrier:
        final Carrier? carrier = widget.carrier;
        if (carrier != null) {
          _carrierName.text = carrier.name;
          _carrierWebsite.text = carrier.website ?? '';
          _carrierContact.text = carrier.contact ?? '';
          _carrierNote.text = carrier.note ?? '';
        }
        break;
      case CardKind.bill:
        final CardBill? bill = widget.bill;
        if (bill != null) {
          _billPhoneId = '${bill.phoneCardId}';
          _billMonth = bill.billMonth;
          _billAmount.text = _amountText(bill.amount);
          _deductedDate = bill.deductedDate;
          _billPaid = bill.paid;
          _billNote.text = bill.note ?? '';
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadPhoneOptions();
          }
        });
    }
    if (widget.kind == CardKind.bill && _billMonth.isEmpty) {
      final DateTime now = DateTime.now();
      _billMonth = '${now.year}-${_two(now.month)}-01';
    }
  }

  /// 两位补零。
  String _two(int value) => value < 10 ? '0$value' : '$value';

  /// 金额转输入框文本；null 保持空串。
  String _amountText(double? value) {
    if (value == null) {
      return '';
    }
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// 扣账账单需要选择手机号卡：拉取全部号卡作为选项。
  Future<void> _loadPhoneOptions() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/lifestyle/phone-cards',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              ))
          .data;
      if (!mounted) {
        return;
      }
      setState(() {
        _phoneOptions = ((json?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) => PhoneCard.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false);
        if (_billPhoneId.isEmpty && _phoneOptions.isNotEmpty) {
          _billPhoneId = '${_phoneOptions.first.id}';
        }
      });
    } on ApiException {
      // 选项加载失败时保留空态，提交前会提示先选择手机号卡。
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _phoneNumber,
      _operator,
      _region,
      _openingBalance,
      _monthlyFee,
      _billDay,
      _dataPlan,
      _callPlan,
      _smsPlan,
      _phoneNote,
      _cardName,
      _cardHolder,
      _bank,
      _cardNumber,
      _cardBalance,
      _creditLimit,
      _billingDay,
      _dueDay,
      _bankNote,
      _carrierName,
      _carrierWebsite,
      _carrierContact,
      _carrierNote,
      _billAmount,
      _billNote,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 可选文本：空串转 null。
  String? _optional(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  /// 可选金额：空串转 null，非法或负数报错。
  double? _optionalAmount(TextEditingController controller, String label) {
    final String text = controller.text.trim();
    if (text.isEmpty) {
      return null;
    }
    final double? value = double.tryParse(text);
    if (value == null || value < 0) {
      throw FormatException('$label需为不小于 0 的数字');
    }
    return value;
  }

  /// 可选 1-31 的日：超出范围报错。
  int? _optionalDay(TextEditingController controller, String label) {
    final String text = controller.text.trim();
    if (text.isEmpty) {
      return null;
    }
    final int? value = int.tryParse(text);
    if (value == null || value < 1 || value > 31) {
      throw FormatException('$label需在 1-31 之间');
    }
    return value;
  }

  /// 选择日期并返回 `YYYY-MM-DD`。
  Future<void> _pickDate(void Function(String) apply, String? current) async {
    final DateTime initial =
        DateTime.tryParse(current ?? '') ?? DateTime.now();
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
      apply('${picked.year}-${_two(picked.month)}-${_two(picked.day)}');
    });
  }

  /// 当前类型的接口路径。
  String get _path {
    switch (widget.kind) {
      case CardKind.phone:
        return '/lifestyle/phone-cards';
      case CardKind.bank:
        return '/lifestyle/bank-cards';
      case CardKind.carrier:
        return '/lifestyle/carriers';
      case CardKind.bill:
        return '/lifestyle/card-bills';
    }
  }

  /// 当前类型标题。
  String get _kindTitle {
    switch (widget.kind) {
      case CardKind.phone:
        return '手机号卡';
      case CardKind.bank:
        return '银行卡';
      case CardKind.carrier:
        return '运营商';
      case CardKind.bill:
        return '扣账账单';
    }
  }

  /// 构建提交 payload；校验失败抛 [FormatException]。
  Map<String, dynamic> _payload() {
    switch (widget.kind) {
      case CardKind.phone:
        final String number = _phoneNumber.text.trim();
        final String operator = _operator.text.trim();
        if (number.isEmpty) {
          throw const FormatException('请填写手机号码');
        }
        if (operator.isEmpty) {
          throw const FormatException('请填写运营商');
        }
        return <String, dynamic>{
          'phone_number': number,
          'operator': operator,
          'region': _optional(_region),
          'opening_balance': _optionalAmount(_openingBalance, '初始余额'),
          'monthly_fee': _optionalAmount(_monthlyFee, '月租'),
          'bill_day': _optionalDay(_billDay, '账单日'),
          'data_plan': _optional(_dataPlan),
          'call_plan': _optional(_callPlan),
          'sms_plan': _optional(_smsPlan),
          'open_date': _openDate,
          'billing_type': _billingType,
          'charge_mode': _chargeMode,
          'auto_charge': _autoCharge,
          'status': _phoneStatus,
          'note': _optional(_phoneNote),
        };
      case CardKind.bank:
        final String name = _cardName.text.trim();
        final String bank = _bank.text.trim();
        if (name.isEmpty) {
          throw const FormatException('请填写卡片别名');
        }
        if (bank.isEmpty) {
          throw const FormatException('请填写银行');
        }
        return <String, dynamic>{
          'card_name': name,
          'card_holder': _optional(_cardHolder),
          'bank': bank,
          'card_category': _cardCategory,
          'card_form': _cardForm,
          'card_number': _optional(_cardNumber),
          'balance': _optionalAmount(_cardBalance, '余额'),
          'credit_limit': _optionalAmount(_creditLimit, '信用额度'),
          'billing_day': _optionalDay(_billingDay, '账单日'),
          'due_day': _optionalDay(_dueDay, '还款日'),
          'expire_date': _expireDate,
          'status': _bankStatus,
          'note': _optional(_bankNote),
        };
      case CardKind.carrier:
        final String name = _carrierName.text.trim();
        if (name.isEmpty) {
          throw const FormatException('请填写平台名称');
        }
        return <String, dynamic>{
          'name': name,
          'website': _optional(_carrierWebsite),
          'contact': _optional(_carrierContact),
          'note': _optional(_carrierNote),
        };
      case CardKind.bill:
        if (_billPhoneId.isEmpty) {
          throw const FormatException('请选择手机号卡');
        }
        if (_billMonth.isEmpty) {
          throw const FormatException('请选择账单月份');
        }
        final double? amount =
            _optionalAmount(_billAmount, '扣账金额');
        if (amount == null) {
          throw const FormatException('请填写扣账金额');
        }
        return <String, dynamic>{
          'phone_card_id': int.tryParse(_billPhoneId) ?? 0,
          'bill_month': _billMonth,
          'amount': amount,
          'deducted_date': _deductedDate,
          'paid': _billPaid,
          'note': _optional(_billNote),
        };
    }
  }

  /// 保存：编辑走 PUT，新增走 POST。
  Future<void> _save() async {
    final Map<String, dynamic> payload;
    try {
      payload = _payload();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.isEditing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '$_path/${widget.id}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          _path,
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(widget.isEditing ? '已更新$_kindTitle' : '已新增$_kindTitle')),
      );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: widget.isEditing ? '编辑$_kindTitle' : '新增$_kindTitle',
      bottomBar: AppPrimaryButton(
        label: _saving ? '保存中…' : '保存',
        onPressed: _saving ? null : _save,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          SectionCard(
            title: _kindTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                ..._fields(theme),
                if (_error != null)
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '余额、本月扣费等派生值由后端按流水计算，表单只填写基础信息。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 按类型渲染字段。
  List<Widget> _fields(ThemeData theme) {
    switch (widget.kind) {
      case CardKind.phone:
        return <Widget>[
          TextField(
            controller: _phoneNumber,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '号码'),
          ),
          AppSelectField<String>(
            label: '运营商',
            value: _operator.text.isEmpty ? _operators.first : _operator.text,
            options: <AppSelectOption<String>>[
              for (final String operator in _operators)
                AppSelectOption<String>(value: operator, label: operator),
              if (_operator.text.isNotEmpty &&
                  !_operators.contains(_operator.text))
                AppSelectOption<String>(
                  value: _operator.text,
                  label: _operator.text,
                ),
            ],
            onChanged: (String value) => setState(() => _operator.text = value),
          ),
          TextField(
            controller: _region,
            decoration: const InputDecoration(
              labelText: '归属地（可选）',
              hintText: '如 广东-深圳',
            ),
          ),
          TextField(
            controller: _openingBalance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '初始余额（可选）',
              hintText: '余额起点；日常增减请用充值 / 校准',
            ),
          ),
          TextField(
            controller: _monthlyFee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '月租（可选）'),
          ),
          TextField(
            controller: _billDay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '账单日（可选）',
              hintText: '1-31',
            ),
          ),
          AppSelectField<String>(
            label: '扣费方式',
            value: _chargeMode,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'monthly', label: '整月一次性'),
              AppSelectOption<String>(
                value: 'daily',
                label: '按天摊销（扣满月租为止）',
              ),
            ],
            onChanged: (String value) => setState(() => _chargeMode = value),
          ),
          AppSelectField<String>(
            label: '自动扣费',
            value: _autoCharge ? 'auto' : 'manual',
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'auto', label: '每日自动结算'),
              AppSelectOption<String>(value: 'manual', label: '仅手动补扣'),
            ],
            onChanged: (String value) =>
                setState(() => _autoCharge = value == 'auto'),
          ),
          TextField(
            controller: _dataPlan,
            decoration: const InputDecoration(
              labelText: '流量套餐（可选）',
              hintText: '如 30GB',
            ),
          ),
          TextField(
            controller: _callPlan,
            decoration: const InputDecoration(
              labelText: '通话（可选）',
              hintText: '如 100分钟',
            ),
          ),
          TextField(
            controller: _smsPlan,
            decoration: const InputDecoration(
              labelText: '短信（可选）',
              hintText: '如 50条',
            ),
          ),
          _DateField(
            label: '开卡时间（可选）',
            value: _openDate,
            onTap: () => _pickDate(
              (String value) => _openDate = value,
              _openDate,
            ),
          ),
          AppSelectField<String>(
            label: '付费方式',
            value: _billingType,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'monthly', label: '按月'),
              AppSelectOption<String>(value: 'one_time', label: '一次性'),
              AppSelectOption<String>(value: 'yearly', label: '按年保号'),
            ],
            onChanged: (String value) => setState(() => _billingType = value),
          ),
          AppSelectField<String>(
            label: '状态',
            value: _phoneStatus,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'active', label: '正常'),
              AppSelectOption<String>(value: 'frozen', label: '冻结'),
              AppSelectOption<String>(value: 'expired', label: '已过期'),
              AppSelectOption<String>(value: 'disabled', label: '已销户'),
            ],
            onChanged: (String value) => setState(() => _phoneStatus = value),
          ),
          TextField(
            controller: _phoneNote,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ];
      case CardKind.bank:
        return <Widget>[
          TextField(
            controller: _cardName,
            decoration: const InputDecoration(
              labelText: '卡片别名',
              hintText: '如 招行工资卡、中信i白金',
            ),
          ),
          TextField(
            controller: _cardHolder,
            decoration: const InputDecoration(labelText: '持卡人（可选）'),
          ),
          TextField(
            controller: _bank,
            decoration: const InputDecoration(
              labelText: '银行',
              hintText: '发卡银行，如 招商银行',
            ),
          ),
          AppSelectField<String>(
            label: '卡类型',
            value: _cardCategory,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'debit', label: '储蓄卡'),
              AppSelectOption<String>(value: 'credit', label: '信用卡'),
            ],
            onChanged: (String value) => setState(() => _cardCategory = value),
          ),
          AppSelectField<String>(
            label: '卡形态',
            value: _cardForm,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'physical', label: '实体卡'),
              AppSelectOption<String>(value: 'virtual', label: '虚拟卡'),
            ],
            onChanged: (String value) => setState(() => _cardForm = value),
          ),
          TextField(
            controller: _cardNumber,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '卡号（可选）'),
          ),
          TextField(
            controller: _cardBalance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '余额（可选）'),
          ),
          TextField(
            controller: _creditLimit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '信用额度（可选）'),
          ),
          TextField(
            controller: _billingDay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '账单日（可选）',
              hintText: '1-31',
            ),
          ),
          TextField(
            controller: _dueDay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '还款日（可选）',
              hintText: '1-31',
            ),
          ),
          _DateField(
            label: '有效期（可选）',
            value: _expireDate,
            onTap: () => _pickDate(
              (String value) => _expireDate = value,
              _expireDate,
            ),
          ),
          AppSelectField<String>(
            label: '状态',
            value: _bankStatus,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'active', label: '正常'),
              AppSelectOption<String>(value: 'frozen', label: '冻结'),
              AppSelectOption<String>(value: 'expired', label: '已过期'),
              AppSelectOption<String>(value: 'closed', label: '已注销'),
            ],
            onChanged: (String value) => setState(() => _bankStatus = value),
          ),
          TextField(
            controller: _bankNote,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ];
      case CardKind.carrier:
        return <Widget>[
          TextField(
            controller: _carrierName,
            decoration: const InputDecoration(labelText: '平台名称'),
          ),
          TextField(
            controller: _carrierWebsite,
            decoration: const InputDecoration(labelText: '官网/链接（可选）'),
          ),
          TextField(
            controller: _carrierContact,
            decoration: const InputDecoration(labelText: '客服电话（可选）'),
          ),
          TextField(
            controller: _carrierNote,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ];
      case CardKind.bill:
        return <Widget>[
          AppSelectField<String>(
            label: '手机号',
            value: _billPhoneId,
            options: <AppSelectOption<String>>[
              const AppSelectOption<String>(value: '', label: '请选择手机号卡'),
              for (final PhoneCard phone in _phoneOptions)
                AppSelectOption<String>(
                  value: '${phone.id}',
                  label: phone.phoneNumber,
                ),
            ],
            onChanged: (String value) => setState(() => _billPhoneId = value),
          ),
          _DateField(
            label: '账单月份',
            value: _billMonth,
            onTap: () => _pickDate(
              (String value) => _billMonth = value,
              _billMonth,
            ),
          ),
          TextField(
            controller: _billAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '扣账金额'),
          ),
          _DateField(
            label: '扣账日期（可选）',
            value: _deductedDate,
            onTap: () => _pickDate(
              (String value) => _deductedDate = value,
              _deductedDate,
            ),
          ),
          AppSelectField<String>(
            label: '是否扣账成功',
            value: _billPaid ? 'true' : 'false',
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'true', label: '成功'),
              AppSelectOption<String>(value: 'false', label: '失败/待扣'),
            ],
            onChanged: (String value) =>
                setState(() => _billPaid = value == 'true'),
          ),
          TextField(
            controller: _billNote,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ];
    }
  }
}

/// 日期选择行。
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          value ?? '未选择',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: value == null ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }
}
