import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增旅行开支：日期 / 行程 / 分类 / 项目 / 原价 / 优惠 / 支付方式 / 备注。
///
/// 对应后端 `POST /finance/travel/details`（`TravelDetailCreate`），
/// 实付由服务端按「原价 - 优惠」计算，本页不重复计算。
class FinanceTravelFormPage extends StatefulWidget {
  const FinanceTravelFormPage({super.key});

  @override
  State<FinanceTravelFormPage> createState() => _FinanceTravelFormPageState();
}

class _FinanceTravelFormPageState extends State<FinanceTravelFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _date = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _item = TextEditingController();
  final TextEditingController _originalPrice = TextEditingController();
  final TextEditingController _discount = TextEditingController();
  final TextEditingController _paymentMethod = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  int? _ledgerId;
  List<AppSelectOption<int?>> _ledgerOptions = <AppSelectOption<int?>>[
    const AppSelectOption<int?>(value: null, label: '未归属行程'),
  ];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date.text = _dateText(_selectedDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadLedgers();
      }
    });
  }

  @override
  void dispose() {
    _date.dispose();
    _category.dispose();
    _item.dispose();
    _originalPrice.dispose();
    _discount.dispose();
    _paymentMethod.dispose();
    _note.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd`（后端 `detail_date` 口径）。
  String _dateText(DateTime value) {
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  /// 行程下拉字典：失败不阻塞表单，只是没有行程可选。
  Future<void> _loadLedgers() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
        '/finance/travel/ledgers',
        queryParameters: <String, dynamic>{'page': 1, 'page_size': 200},
      ))
          .data;
      if (!mounted) {
        return;
      }
      final List<Map> items =
          ((json?['items'] as List?) ?? const <dynamic>[]).whereType<Map>().toList();
      setState(() {
        _ledgerOptions = <AppSelectOption<int?>>[
          const AppSelectOption<int?>(value: null, label: '未归属行程'),
          for (final Map item in items)
            AppSelectOption<int?>(
              value: (item['id'] as num?)?.toInt(),
              label: (item['name'] as String?) ?? '未命名行程',
            ),
        ];
        _loading = false;
      });
    } on ApiException {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDate = picked;
      _date.text = _dateText(picked);
    });
  }

  /// 保存：实付交给服务端计算，成功后返回列表并刷新。
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
      'ledger_id': _ledgerId,
      'detail_date': _date.text,
      'category': _category.text.trim(),
      'item': _item.text.trim(),
      'original_price': _parseAmount(_originalPrice.text),
      'discount': _parseAmount(_discount.text, fallback: 0),
      'payment_method':
          _paymentMethod.text.trim().isEmpty ? null : _paymentMethod.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      await scope.apiClient.post<Map<String, dynamic>>(
        '/finance/travel/details',
        data: payload,
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已新增旅行开支')));
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

  /// 金额字符串转 double：去掉千分位，空串按 [fallback]。
  double _parseAmount(String raw, {double? fallback}) {
    final String text = raw.replaceAll(',', '').trim();
    if (text.isEmpty && fallback != null) {
      return fallback;
    }
    return double.tryParse(text) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '新增旅行开支',
      bottomBar: SizedBox(
        width: double.infinity,
        child: AppPrimaryButton(
          label: '保存',
          loading: _saving,
          onPressed: _loading || _saving ? null : _save,
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
                        title: '开支信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _item,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '项目',
                                hintText: '例如 高铁票、酒店',
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '请填写项目名称';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _category,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '分类',
                                hintText: '例如 交通、住宿、餐饮',
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '请填写分类';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _originalPrice,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: '原价',
                                hintText: '0.00',
                                prefixText: '¥ ',
                              ),
                              validator: (String? value) {
                                final double? parsed = double.tryParse(
                                  (value ?? '').replaceAll(',', '').trim(),
                                );
                                if (parsed == null || parsed <= 0) {
                                  return '请输入大于 0 的原价';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _discount,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: '优惠（可选）',
                                hintText: '0.00',
                                prefixText: '¥ ',
                              ),
                              validator: (String? value) {
                                final String text =
                                    (value ?? '').replaceAll(',', '').trim();
                                if (text.isEmpty) {
                                  return null;
                                }
                                final double? parsed = double.tryParse(text);
                                if (parsed == null || parsed < 0) {
                                  return '请输入不小于 0 的优惠金额';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _date,
                              readOnly: true,
                              onTap: _pickDate,
                              decoration: const InputDecoration(
                                labelText: '消费日期',
                                suffixIcon:
                                    Icon(Icons.calendar_today_outlined),
                              ),
                            ),
                            AppSelectField<int?>(
                              label: '行程',
                              value: _ledgerId,
                              options: _ledgerOptions,
                              onChanged: (int? value) =>
                                  setState(() => _ledgerId = value),
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: '补充信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _paymentMethod,
                              decoration: const InputDecoration(
                                labelText: '支付方式（可选）',
                                hintText: '例如 支付宝、微信',
                              ),
                            ),
                            TextFormField(
                              controller: _note,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: '备注（可选）',
                                hintText: '例如 同行人数、报销信息',
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
}
