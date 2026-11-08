import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增 / 编辑旅行开支：日期 / 起止时间 / 行程 / 分类 / 项目 / 原价 / 优惠 /
/// 交通信息 / 支付方式 / 备注。
///
/// 对应后端 `POST /finance/travel/details` 与
/// `PUT /finance/travel/details/{id}`（`TravelDetailCreate`），
/// 实付由服务端按「原价 - 优惠」计算，本页不重复计算。
class FinanceTravelFormPage extends StatefulWidget {
  const FinanceTravelFormPage({super.key, this.recordId, this.initial});

  /// 非空表示编辑模式。
  final int? recordId;
  final TravelDetail? initial;

  bool get isEditing => recordId != null;

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
  final TextEditingController _beginTime = TextEditingController();
  final TextEditingController _endTime = TextEditingController();
  final TextEditingController _transportInfo = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  int? _ledgerId;
  List<AppSelectOption<int?>> _ledgerOptions = <AppSelectOption<int?>>[
    const AppSelectOption<int?>(value: null, label: '未归属行程'),
  ];

  /// 支付方式：来自 `/finance/travel/payment-channels` 字典；空串表示未选。
  String _paymentMethod = '';
  List<String> _payChannels = const <String>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final TravelDetail? initial = widget.initial;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadDictionaries();
      }
    });
  }

  /// 用列表快照预填；空值保持空串，不写 0。
  void _apply(TravelDetail detail) {
    _selectedDate = DateTime.tryParse(detail.detailDate) ?? DateTime.now();
    _ledgerId = detail.ledgerId;
    _category.text = detail.category;
    _item.text = detail.item;
    _originalPrice.text = _amountText(detail.originalPrice);
    _discount.text = _amountText(detail.discount);
    _beginTime.text = _timeText(detail.beginTime);
    _endTime.text = _timeText(detail.endTime);
    _transportInfo.text = detail.transportInfo ?? '';
    _paymentMethod = detail.paymentMethod ?? '';
    _note.text = detail.note ?? '';
  }

  /// 金额转输入框文本。
  String _amountText(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// `HH:mm:ss` / `HH:mm` → `HH:mm`；null 保持空串。
  String _timeText(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }
    return value.length >= 5 ? value.substring(0, 5) : value;
  }

  /// 深链进入且无快照时按 id 拉取。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/finance/travel/details/${widget.recordId}',
              ))
          .data;
      if (!mounted || json == null) {
        return;
      }
      setState(() {
        _apply(TravelDetail.fromJson(json));
        _date.text = _dateText(_selectedDate);
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _category.dispose();
    _item.dispose();
    _originalPrice.dispose();
    _discount.dispose();
    _beginTime.dispose();
    _endTime.dispose();
    _transportInfo.dispose();
    _note.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd`（后端 `detail_date` 口径）。
  String _dateText(DateTime value) {
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  /// 行程与支付方式字典：任一失败都不阻塞表单，只是对应选项为空。
  Future<void> _loadDictionaries() async {
    final AppScope scope = AppScope.of(context);
    try {
      final List<Object?> responses = await Future.wait<Object?>(<Future<Object?>>[
        scope.apiClient
            .get<Map<String, dynamic>>(
              '/finance/travel/ledgers',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
            )
            .then((value) => value.data)
            .catchError((Object _) => null),
        scope.apiClient
            .get<Map<String, dynamic>>(
              '/finance/travel/payment-channels',
              queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
            )
            .then((value) => value.data)
            .catchError((Object _) => null),
      ]);
      if (!mounted) {
        return;
      }
      final Map<String, dynamic>? ledgerJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? channelJson =
          responses[1] as Map<String, dynamic>?;
      final List<Map> ledgers =
          ((ledgerJson?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .toList();
      final List<String> channels =
          ((channelJson?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map item) => item['name'] as String? ?? '')
              .where((String name) => name.isNotEmpty)
              .toList();
      setState(() {
        _ledgerOptions = <AppSelectOption<int?>>[
          const AppSelectOption<int?>(value: null, label: '未归属行程'),
          for (final Map item in ledgers)
            AppSelectOption<int?>(
              value: (item['id'] as num?)?.toInt(),
              label: (item['name'] as String?) ?? '未命名行程',
            ),
        ];
        _payChannels = channels;
        _loading = false;
      });
    } on ApiException {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 选择开始 / 结束时间（HH:mm），与网页端 `input[type=time]` 同口径。
  Future<void> _pickTime(TextEditingController controller) async {
    final String raw = controller.text.trim();
    final List<String> parts = raw.split(':');
    final TimeOfDay initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) {
      return;
    }
    String two(int value) => value < 10 ? '0$value' : '$value';
    setState(() => controller.text = '${two(picked.hour)}:${two(picked.minute)}');
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
      'begin_time': _beginTime.text.trim().isEmpty ? null : _beginTime.text,
      'end_time': _endTime.text.trim().isEmpty ? null : _endTime.text,
      'category': _category.text.trim(),
      'item': _item.text.trim(),
      'original_price': _parseAmount(_originalPrice.text),
      'discount': _parseAmount(_discount.text, fallback: 0),
      'transport_info':
          _transportInfo.text.trim().isEmpty ? null : _transportInfo.text.trim(),
      'payment_method': _paymentMethod.isEmpty ? null : _paymentMethod,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (widget.isEditing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/travel/details/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/finance/travel/details',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(widget.isEditing ? '已更新旅行开支' : '已新增旅行开支')),
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
      title: widget.isEditing ? '编辑旅行开支' : '新增旅行开支',
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
                            Row(
                              spacing: 12,
                              children: <Widget>[
                                Expanded(
                                  child: TextFormField(
                                    controller: _beginTime,
                                    readOnly: true,
                                    onTap: () => _pickTime(_beginTime),
                                    decoration: const InputDecoration(
                                      labelText: '开始时间',
                                      hintText: '可选',
                                      suffixIcon:
                                          Icon(Icons.schedule_outlined),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _endTime,
                                    readOnly: true,
                                    onTap: () => _pickTime(_endTime),
                                    decoration: const InputDecoration(
                                      labelText: '结束时间',
                                      hintText: '可选',
                                      suffixIcon:
                                          Icon(Icons.schedule_outlined),
                                    ),
                                  ),
                                ),
                              ],
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
                            AppSelectField<String>(
                              label: '支付方式',
                              value: _paymentMethod,
                              options: <AppSelectOption<String>>[
                                const AppSelectOption<String>(
                                  value: '',
                                  label: '未选择',
                                ),
                                for (final String name in _payChannels)
                                  AppSelectOption<String>(
                                    value: name,
                                    label: name,
                                  ),
                                // 历史值可能已从字典删除：保留原值可继续保存。
                                if (_paymentMethod.isNotEmpty &&
                                    !_payChannels.contains(_paymentMethod))
                                  AppSelectOption<String>(
                                    value: _paymentMethod,
                                    label: _paymentMethod,
                                  ),
                              ],
                              onChanged: (String value) =>
                                  setState(() => _paymentMethod = value),
                            ),
                            TextFormField(
                              controller: _transportInfo,
                              decoration: const InputDecoration(
                                labelText: '交通信息（可选）',
                                hintText: '例如 高铁 G1234 二等座',
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
