import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/app_select.dart';
import '../../../shared/widgets/root_page_scaffold.dart';
import '../../../shared/widgets/section_card.dart';

/// 账单记录类型：对应网页端 `/finance/bills` 的三个 Tab。
enum BillKind {
  /// 网贷借还（`/finance/loan-bills`）。
  loan,

  /// 房租水电 → 租房（`/finance/housing`）。
  housing,

  /// 房租水电 → 水电缴费（`/finance/utilities`）。
  utility,

  /// 服务订阅（`/finance/subscriptions`）。
  subscription,
}

/// 解析路由查询参数里的类型；未知值退回网贷。
BillKind billKindFromParam(String? value) {
  switch (value) {
    case 'housing':
      return BillKind.housing;
    case 'utility':
      return BillKind.utility;
    case 'subscription':
      return BillKind.subscription;
    default:
      return BillKind.loan;
  }
}

/// 账单新增 / 编辑表单（四类记录共用）。
///
/// 写操作一律在线提交：账单涉及金额，失败时保留表单让用户重试，
/// 避免静默进入离线队列后重复补录产生重复扣款记录。
class FinanceBillFormPage extends StatefulWidget {
  const FinanceBillFormPage({super.key, required this.kind, this.id});

  final BillKind kind;
  final int? id;

  @override
  State<FinanceBillFormPage> createState() => _FinanceBillFormPageState();
}

class _FinanceBillFormPageState extends State<FinanceBillFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text =
      <String, TextEditingController>{};

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  int? _platformId;
  String _loanStatus = 'pending';
  bool _graceApplied = false;
  DateTime? _billMonth;
  DateTime? _dueDate;

  String _rentTerm = 'monthly';
  DateTime? _moveInDate;
  DateTime? _moveOutDate;

  int? _housingId;
  String _feeType = 'electricity';
  bool _paid = false;

  String _billingCycle = 'month';
  String _subStatus = 'active';
  bool _autoRenew = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _category;

  List<({int id, String name})> _platforms = <({int id, String name})>[];
  List<({int id, String name})> _housings = <({int id, String name})>[];
  List<String> _categories = <String>[];

  bool get _editing => widget.id != null;

  /// 各类型对应的增删改查前缀（与网页端同源）。
  String get _resource {
    switch (widget.kind) {
      case BillKind.loan:
        return '/finance/loan-bills';
      case BillKind.housing:
        return '/finance/housing';
      case BillKind.utility:
        return '/finance/utilities';
      case BillKind.subscription:
        return '/finance/subscriptions';
    }
  }

  @override
  void initState() {
    super.initState();
    // 首帧后再取 AppScope：initState 内不允许依赖 InheritedWidget。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _init();
      }
    });
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 懒创建文本控制器，避免为四类记录一次性声明几十个字段。
  TextEditingController _ctl(String key) =>
      _text.putIfAbsent(key, TextEditingController.new);

  String _value(String key) => _ctl(key).text.trim();

  /// 加载下拉选项与编辑态数据。
  Future<void> _init() async {
    final AppScope scope = AppScope.of(context);
    setState(() => _loading = _editing);
    try {
      if (widget.kind == BillKind.loan) {
        final Map<String, dynamic>? json = (await scope.apiClient
                .get<Map<String, dynamic>>('/finance/loan-platforms',
                    queryParameters: <String, dynamic>{'page_size': 100}))
            .data;
        _platforms = ((json?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) => (
                  id: (item['id'] as num?)?.toInt() ?? 0,
                  name: item['name'] as String? ?? '',
                ))
            .toList();
      } else if (widget.kind == BillKind.utility) {
        final Map<String, dynamic>? json = (await scope.apiClient
                .get<Map<String, dynamic>>('/finance/housing',
                    queryParameters: <String, dynamic>{'page_size': 100}))
            .data;
        _housings = ((json?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) => (
                  id: (item['id'] as num?)?.toInt() ?? 0,
                  name: item['name'] as String? ?? '',
                ))
            .toList();
      } else if (widget.kind == BillKind.subscription) {
        final Map<String, dynamic>? json = (await scope.apiClient
                .get<Map<String, dynamic>>('/finance/subscription-categories',
                    queryParameters: <String, dynamic>{'page_size': 100}))
            .data;
        _categories = ((json?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item['name'] as String? ?? '')
            .where((String value) => value.isNotEmpty)
            .toList();
      }
      if (_editing) {
        final Map<String, dynamic>? json = (await scope.apiClient
                .get<Map<String, dynamic>>('$_resource/${widget.id}'))
            .data;
        if (json != null) {
          _fill(json);
        }
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 编辑态回填：文本进控制器，日期/枚举/开关进状态。
  void _fill(Map<String, dynamic> json) {
    void put(String key, Object? value) {
      _ctl(key).text = value == null ? '' : '$value';
    }

    switch (widget.kind) {
      case BillKind.loan:
        put('amount', json['amount']);
        put('interest', json['interest'] ?? 0);
        put('paid_amount', json['paid_amount'] ?? 0);
        put('note', json['note']);
        _platformId = (json['platform_id'] as num?)?.toInt();
        _billMonth = _parseDate(json['bill_month'] as String?);
        _dueDate = _parseDate(json['due_date'] as String?);
        _loanStatus = json['status'] as String? ?? 'pending';
        _graceApplied = json['grace_applied'] as bool? ?? false;
      case BillKind.housing:
        put('name', json['name']);
        put('short_name', json['short_name']);
        put('channel', json['channel']);
        put('orientation', json['orientation']);
        put('actual_monthly_rent', json['actual_monthly_rent']);
        put('deposit', json['deposit'] ?? 0);
        put('deposit_refunded', json['deposit_refunded'] ?? 0);
        put('deposit_refund_channel', json['deposit_refund_channel']);
        put('agent_fee', json['agent_fee'] ?? 0);
        put('clean_fee', json['clean_fee'] ?? 0);
        put('service_fee', json['service_fee'] ?? 0);
        put('laundry_fee', json['laundry_fee'] ?? 0);
        put('note', json['note']);
        _moveInDate = _parseDate(json['move_in_date'] as String?);
        _moveOutDate = _parseDate(json['move_out_date'] as String?);
        _rentTerm = json['rent_term'] as String? ?? 'monthly';
      case BillKind.utility:
        put('amount', json['amount']);
        put('note', json['note']);
        _housingId = (json['housing_id'] as num?)?.toInt();
        _billMonth = _parseDate(json['bill_month'] as String?);
        _dueDate = _parseDate(json['due_date'] as String?);
        _feeType = json['fee_type'] as String? ?? 'electricity';
        _paid = json['paid'] as bool? ?? false;
      case BillKind.subscription:
        put('name', json['name']);
        put('plan_name', json['plan_name']);
        put('amount', json['amount']);
        put('note', json['note']);
        _category = json['category'] as String?;
        _billingCycle = json['billing_cycle'] as String? ?? 'month';
        _startDate = _parseDate(json['start_date'] as String?);
        _endDate = _parseDate(json['end_date'] as String?);
        _autoRenew = json['auto_renew'] as bool? ?? false;
        _subStatus = json['status'] as String? ?? 'active';
    }
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  /// `yyyy-MM-dd`（后端日期口径）。
  static String _dateText(DateTime value) {
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  /// `yyyy-MM`（账单月份展示）。
  static String _monthText(DateTime value) {
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${value.year}-${two(value.month)}';
  }

  /// 可选字段：空串 → null，避免后端把空字符串当有效值。
  String? _optional(String key) {
    final String value = _value(key);
    return value.isEmpty ? null : value;
  }

  /// 金额字段：空串按 0，非法数字返回 null 由校验拦截。
  double? _number(String key) {
    final String value = _value(key);
    if (value.isEmpty) {
      return 0;
    }
    return double.tryParse(value);
  }

  /// 数字校验：必填、非负。
  String? _numberValidator(String? value, {bool required = true}) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return required ? '请填写金额' : null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return '请输入有效数字';
    }
    if (parsed < 0) {
      return '不能为负数';
    }
    return null;
  }

  String? _requiredText(String? value) {
    return (value ?? '').trim().isEmpty ? '请填写' : null;
  }

  /// 按类型构造与网页端一致的请求体。
  Map<String, dynamic> _payload() {
    switch (widget.kind) {
      case BillKind.loan:
        return <String, dynamic>{
          'platform_id': _platformId,
          'bill_month': _dateText(_billMonth!),
          'due_date': _dueDate == null ? null : _dateText(_dueDate!),
          'amount': _number('amount') ?? 0,
          'interest': _number('interest') ?? 0,
          'paid_amount': _number('paid_amount') ?? 0,
          'status': _loanStatus,
          'grace_applied': _graceApplied,
          'note': _optional('note'),
        };
      case BillKind.housing:
        return <String, dynamic>{
          'name': _value('name'),
          'short_name': _optional('short_name'),
          'channel': _optional('channel'),
          'orientation': _optional('orientation'),
          'move_in_date': _dateText(_moveInDate!),
          'move_out_date':
              _moveOutDate == null ? null : _dateText(_moveOutDate!),
          'rent_term': _rentTerm,
          'actual_monthly_rent': _number('actual_monthly_rent') ?? 0,
          'deposit': _number('deposit') ?? 0,
          'deposit_refunded': _number('deposit_refunded') ?? 0,
          'deposit_refund_channel': _optional('deposit_refund_channel'),
          'agent_fee': _number('agent_fee') ?? 0,
          'clean_fee': _number('clean_fee') ?? 0,
          'service_fee': _number('service_fee') ?? 0,
          'laundry_fee': _number('laundry_fee') ?? 0,
          'note': _optional('note'),
        };
      case BillKind.utility:
        return <String, dynamic>{
          'housing_id': _housingId,
          'bill_month': _dateText(_billMonth!),
          'fee_type': _feeType,
          'amount': _number('amount') ?? 0,
          'due_date': _dueDate == null ? null : _dateText(_dueDate!),
          'paid': _paid,
          'note': _optional('note'),
        };
      case BillKind.subscription:
        return <String, dynamic>{
          'name': _value('name'),
          'plan_name': _optional('plan_name'),
          'category': _category == null || _category!.trim().isEmpty
              ? '会员'
              : _category,
          'billing_cycle': _billingCycle,
          'amount': _number('amount') ?? 0,
          'start_date': _dateText(_startDate!),
          'end_date': _endDate == null ? null : _dateText(_endDate!),
          'auto_renew': _autoRenew,
          'status': _subStatus,
          'note': _optional('note'),
        };
    }
  }

  /// 必填的日期在提交前兜底校验（日期控件没有 FormField）。
  bool _validateDates() {
    switch (widget.kind) {
      case BillKind.loan:
      case BillKind.utility:
        if (_billMonth == null) {
          setState(() => _error = '请选择账单月份');
          return false;
        }
      case BillKind.housing:
        if (_moveInDate == null) {
          setState(() => _error = '请选择入住日期');
          return false;
        }
      case BillKind.subscription:
        if (_startDate == null) {
          setState(() => _error = '请选择开通日期');
          return false;
        }
    }
    return true;
  }

  /// 保存：新增走 POST、编辑走 PUT；失败保留表单并可重试。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || !_validateDates()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：账单涉及金额，需联网后保存');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '$_resource/${widget.id}',
          data: _payload(),
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          _resource,
          data: _payload(),
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? '已保存修改' : '已新增$_kindLabel')),
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

  /// 删除：二次确认说明「删了什么、能不能恢复」，成功后返回列表刷新。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('删除$_kindLabel？'),
          content: Text('$_deleteDescription\n删除后无法恢复。'),
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
      await scope.apiClient.delete<dynamic>('$_resource/${widget.id}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text('已删除$_kindLabel')));
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

  /// 当前类型的短名称。
  String get _kindLabel {
    switch (widget.kind) {
      case BillKind.loan:
        return '账单';
      case BillKind.housing:
        return '住房记录';
      case BillKind.utility:
        return '水电缴费记录';
      case BillKind.subscription:
        return '订阅';
    }
  }

  /// 删除确认里的具体对象说明，避免只写「删除」。
  String get _deleteDescription {
    switch (widget.kind) {
      case BillKind.loan:
        return '将删除 ${_monthText(_billMonth ?? DateTime.now())} 的网贷账单'
            '（应还 ¥${_number('amount') ?? 0}），不会删除平台资料。';
      case BillKind.housing:
        return '将删除住房「${_value('name')}」及其基本信息，'
            '不会自动删除关联的水电缴费记录。';
      case BillKind.utility:
        return '将删除 ${_monthText(_billMonth ?? DateTime.now())} 的'
            '${_feeTypeLabel(_feeType)}记录（¥${_number('amount') ?? 0}）。';
      case BillKind.subscription:
        return '将删除订阅「${_value('name')}」，不影响已发生的账单记录。';
    }
  }

  static String _feeTypeLabel(String value) {
    for (final ({String value, String label}) item in _feeTypes) {
      if (item.value == value) {
        return item.label;
      }
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return DetailPageScaffold(
      title: _editing ? '编辑$_kindLabel' : '新增$_kindLabel',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                // 卡片与按钮之间留 16dp，按钮距底部 32dp + 系统安全区。
                padding: const EdgeInsets.only(bottom: 32),
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: <Widget>[
                  SectionCard(
                    title: '基本信息',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: _fields(),
                    ),
                  ),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
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
                  Text(
                    '账单涉及金额，保存与删除均在线提交；网络异常时表单会保留，'
                    '不会静默进入离线队列。',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// 按类型渲染表单字段。
  List<Widget> _fields() {
    switch (widget.kind) {
      case BillKind.loan:
        return <Widget>[
          _dropdown<int>(
            label: '借款平台',
            value: _platformId,
            hint: '不指定平台',
            items: <({int value, String label})>[
              for (final ({int id, String name}) item in _platforms)
                (value: item.id, label: item.name),
            ],
            onChanged: (int? value) => setState(() => _platformId = value),
          ),
          _dateField(
            label: '账单月份',
            text: _billMonth == null ? '请选择' : _monthText(_billMonth!),
            onTap: () => _pickMonth((DateTime value) {
              setState(() => _billMonth = DateTime(value.year, value.month, 1));
            }),
          ),
          _dateField(
            label: '到期日（可选）',
            text: _dueDate == null ? '未设置' : _dateText(_dueDate!),
            onTap: () => _pickDate((DateTime value) {
              setState(() => _dueDate = value);
            }),
          ),
          _textField('amount', '应还金额', numeric: true, required: true),
          _textField('interest', '其中利息', numeric: true),
          _textField('paid_amount', '已还金额', numeric: true),
          _dropdown<String>(
            label: '状态',
            value: _loanStatus,
            items: const <({String value, String label})>[
              (value: 'pending', label: '待还'),
              (value: 'partial', label: '部分还'),
              (value: 'cleared', label: '已结清'),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _loanStatus = value);
              }
            },
          ),
          _switchTile(
            label: '已申请容时',
            value: _graceApplied,
            onChanged: (bool value) => setState(() => _graceApplied = value),
          ),
          _textField('note', '备注'),
        ];
      case BillKind.housing:
        return <Widget>[
          _textField('name', '房屋名称', required: true),
          _textField('short_name', '显示缩写'),
          _textField('channel', '租房渠道'),
          _textField('orientation', '房屋朝向'),
          _dateField(
            label: '入住日期',
            text: _moveInDate == null ? '请选择' : _dateText(_moveInDate!),
            onTap: () => _pickDate((DateTime value) {
              setState(() => _moveInDate = value);
            }),
          ),
          _dateField(
            label: '退租日期（可选）',
            text: _moveOutDate == null ? '未设置' : _dateText(_moveOutDate!),
            onTap: () => _pickDate((DateTime value) {
              setState(() => _moveOutDate = value);
            }),
            onClear: () => setState(() => _moveOutDate = null),
          ),
          _dropdown<String>(
            label: '付款期次',
            value: _rentTerm,
            items: const <({String value, String label})>[
              (value: 'monthly', label: '月付'),
              (value: 'quarterly', label: '季付'),
              (value: 'one_time', label: '一次性'),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _rentTerm = value);
              }
            },
          ),
          _textField(
            'actual_monthly_rent',
            '实际月租',
            numeric: true,
            required: true,
          ),
          _textField('deposit', '押金', numeric: true),
          _textField('deposit_refunded', '已扣押金', numeric: true),
          _textField('deposit_refund_channel', '押金退还渠道'),
          _textField('agent_fee', '中介费', numeric: true),
          _textField('clean_fee', '保洁费', numeric: true),
          _textField('service_fee', '服务费', numeric: true),
          _textField('laundry_fee', '洗衣费', numeric: true),
          _textField('note', '备注'),
        ];
      case BillKind.utility:
        return <Widget>[
          _dropdown<int>(
            label: '所属住房',
            value: _housingId,
            hint: '不关联住房',
            items: <({int value, String label})>[
              for (final ({int id, String name}) item in _housings)
                (value: item.id, label: item.name),
            ],
            onChanged: (int? value) => setState(() => _housingId = value),
          ),
          _dateField(
            label: '账单月份',
            text: _billMonth == null ? '请选择' : _monthText(_billMonth!),
            onTap: () => _pickMonth((DateTime value) {
              setState(() => _billMonth = DateTime(value.year, value.month, 1));
            }),
          ),
          _dropdown<String>(
            label: '费用类型',
            value: _feeType,
            items: _feeTypes,
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _feeType = value);
              }
            },
          ),
          _textField('amount', '金额', numeric: true, required: true),
          _dateField(
            label: '到期日（可选）',
            text: _dueDate == null ? '未设置' : _dateText(_dueDate!),
            onTap: () => _pickDate((DateTime value) {
              setState(() => _dueDate = value);
            }),
            onClear: () => setState(() => _dueDate = null),
          ),
          _switchTile(
            label: '已缴费',
            value: _paid,
            onChanged: (bool value) => setState(() => _paid = value),
          ),
          _textField('note', '备注'),
        ];
      case BillKind.subscription:
        return <Widget>[
          _textField('name', '订阅名称', required: true),
          _textField('plan_name', '方案名称'),
          _dropdown<String>(
            label: '分类',
            value: _category,
            hint: '默认「会员」',
            items: <({String value, String label})>[
              for (final String item in _categories)
                (value: item, label: item),
              if (_category != null &&
                  !_categories.contains(_category))
                (value: _category!, label: _category!),
            ],
            onChanged: (String? value) => setState(() => _category = value),
          ),
          _dropdown<String>(
            label: '计费周期',
            value: _billingCycle,
            items: const <({String value, String label})>[
              (value: 'month', label: '月付'),
              (value: 'quarter', label: '季付'),
              (value: 'year', label: '年付'),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _billingCycle = value);
              }
            },
          ),
          _textField('amount', '每期金额', numeric: true, required: true),
          _dateField(
            label: '开通日期（必填）',
            text: _startDate == null ? '请选择' : _dateText(_startDate!),
            onTap: () => _pickDate((DateTime value) {
              setState(() => _startDate = value);
            }),
          ),
          _dateField(
            label: '到期日期（可选）',
            text: _endDate == null ? '未设置' : _dateText(_endDate!),
            onTap: () => _pickDate((DateTime value) {
              setState(() => _endDate = value);
            }),
            onClear: () => setState(() => _endDate = null),
          ),
          _switchTile(
            label: '自动续费',
            value: _autoRenew,
            onChanged: (bool value) => setState(() => _autoRenew = value),
          ),
          _dropdown<String>(
            label: '状态',
            value: _subStatus,
            items: const <({String value, String label})>[
              (value: 'active', label: '生效中'),
              (value: 'expired', label: '已过期'),
              (value: 'cancelled', label: '已取消'),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _subStatus = value);
              }
            },
          ),
          _textField('note', '备注'),
        ];
    }
  }

  static const List<({String value, String label})> _feeTypes =
      <({String value, String label})>[
    (value: 'water', label: '水费'),
    (value: 'electricity', label: '电费'),
    (value: 'gas', label: '燃气费'),
    (value: 'property', label: '物业费'),
    (value: 'broadband', label: '宽带费'),
    (value: 'other', label: '其他'),
  ];

  /// 文本输入：数字字段统一用小数键盘并带非负校验。
  Widget _textField(
    String key,
    String label, {
    bool numeric = false,
    bool required = false,
  }) {
    return TextFormField(
      controller: _ctl(key),
      keyboardType:
          numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
      decoration: InputDecoration(labelText: required ? '$label *' : label),
      validator: numeric
          ? (String? value) => _numberValidator(value, required: required)
          : (required ? _requiredText : null),
    );
  }

  /// 日期展示行：点击选择；可选字段带「清除」。
  Widget _dateField({
    required String label,
    required String text,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                tooltip: '清除',
                icon: const Icon(Icons.clear, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  /// 下拉选择统一走 AppSelectField：受控值回填后立即反映，外观与输入框一致。
  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<({T value, String label})> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    return AppSelectField<T?>(
      label: label,
      value: value,
      hint: hint ?? '请选择',
      options: <AppSelectOption<T?>>[
        for (final ({T value, String label}) item in items)
          AppSelectOption<T?>(value: item.value, label: item.label),
      ],
      onChanged: onChanged,
    );
  }

  Widget _switchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }

  /// 选择日期（不限制过去/未来，账单可能补录）。
  Future<void> _pickDate(void Function(DateTime) onPicked) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  /// 选择月份：只取年月，日固定为 1。
  Future<void> _pickMonth(void Function(DateTime) onPicked) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, 1),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: '选择账单月份',
    );
    if (picked != null) {
      onPicked(picked);
    }
  }
}
