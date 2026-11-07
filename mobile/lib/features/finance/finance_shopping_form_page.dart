import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 购物记录新增 / 编辑：日期 / 商品名 / 金额 / 平台 / 分类 / 备注。
///
/// 后端 `PUT /finance/shopping/records/{id}` 使用 `ShoppingCreate` **全量覆盖**
/// （`payload.model_dump()`，不是 `exclude_unset`），因此编辑保存时必须回传
/// 规格、单价、订单号、账本等本页未展示的字段，避免被置空。
/// [recordId] 为空表示新增，走 `POST /finance/shopping/records`。
///
/// 编辑页主操作按全 App 约定放在底部：左「保存」、右「删除」；删除二次确认。
class FinanceShoppingFormPage extends StatefulWidget {
  const FinanceShoppingFormPage({
    super.key,
    this.recordId,
    this.initial,
  });

  /// 为空表示新增。
  final int? recordId;

  /// 列表页带过来的快照；为空时按 [recordId] 拉取。
  final ShoppingRecord? initial;

  @override
  State<FinanceShoppingFormPage> createState() =>
      _FinanceShoppingFormPageState();
}

class _FinanceShoppingFormPageState extends State<FinanceShoppingFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _product = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  ShoppingRecord? _record;
  DateTime _date = DateTime.now();
  int? _platformId;
  int? _categoryId;

  List<NamedOption> _platforms = <NamedOption>[];
  List<_CategoryOption> _categories = <_CategoryOption>[];

  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  /// 新增模式：没有记录 ID，保存走 POST。
  bool get _creating => widget.recordId == null;

  @override
  void initState() {
    super.initState();
    final ShoppingRecord? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
      _loading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _bootstrap();
      }
    });
  }

  @override
  void dispose() {
    _product.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用快照预填表单（金额去掉无意义的尾零）。
  void _apply(ShoppingRecord record) {
    _record = record;
    _date = DateTime.tryParse(record.recordDate) ?? DateTime.now();
    _product.text = record.productName;
    _amount.text = _plain(record.totalPrice);
    _note.text = record.note ?? '';
    _platformId = record.platformId;
    _categoryId = record.categoryId;
  }

  /// 串行拉记录与字典：任一失败都停留在可重试的错误态，不提交空表单。
  Future<void> _bootstrap() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_creating && _record == null) {
        final Map<String, dynamic>? json = (await scope.apiClient
                .get<Map<String, dynamic>>(
                    '/finance/shopping/records/${widget.recordId}'))
            .data;
        if (json == null) {
          throw const ApiException(
            kind: ApiErrorKind.badResponse,
            message: '购物记录返回为空',
          );
        }
        _apply(ShoppingRecord.fromJson(json));
      }
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/finance/shopping/platforms',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<List<dynamic>>('/finance/shopping/categories')
              .then((value) => value.data),
        ],
      );
      final Map<String, dynamic>? platformJson =
          responses[0] as Map<String, dynamic>?;
      if (!mounted) {
        return;
      }
      setState(() {
        _platforms = ((platformJson?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) =>
                NamedOption.fromJson(item.cast<String, dynamic>()))
            .toList();
        _categories = (responses[1] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) =>
                _CategoryOption.fromJson(item.cast<String, dynamic>()))
            .toList();
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

  /// 保存：全量回传 `ShoppingCreate` 字段，未在本页展示的字段沿用原值。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final ShoppingRecord? record = _record;
    if (!_creating && record == null) {
      setState(() => _error = '记录尚未加载完成');
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：编辑购物记录需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final double amount =
        double.parse(_amount.text.replaceAll(',', '').trim());
    final Map<String, dynamic> payload = <String, dynamic>{
      'record_date': _dateText,
      'product_name': _product.text.trim(),
      'total_price': amount,
      'platform_id': _platformId,
      'category_id': _categoryId,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      // 编辑时本页不展示但后端会全量覆盖的字段，按原值回传。
      if (record != null) ...<String, dynamic>{
        'spec': record.spec,
        'unit_price': record.unitPrice,
        'order_no': record.orderNo,
        'ledger_id': record.ledgerId,
      },
    };
    try {
      if (_creating) {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/finance/shopping/records',
          data: payload,
        );
      } else {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/shopping/records/${widget.recordId}',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('已保存 ${_product.text.trim()} $amount 元')),
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

  /// 删除：确认文案写明汇总与统计会一起回退。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该条购物记录？'),
          content: Text(
            '将删除「${_product.text.trim()}」$_dateText 的记录。\n'
            '删除后消费总额、笔数、平均单笔与平台统计会同步回退，且无法恢复。',
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
      await scope.apiClient
          .delete<dynamic>('/finance/shopping/records/${widget.recordId}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该条购物记录')));
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
      title: _creating ? '新增购物记录' : '编辑购物记录',
      bottomBar: _creating
          ? SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: '保存',
                loading: _saving,
                onPressed: _loading || _saving ? null : _save,
              ),
            )
          : AppActionRow(
              first: AppPrimaryButton(
                label: '保存',
                loading: _saving,
                onPressed: _loading || _saving || _deleting ? null : _save,
              ),
              second: AppDangerButton(
                label: '删除',
                loading: _deleting,
                onPressed: _loading || _saving || _deleting ? null : _delete,
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
                        title: '记录信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _product,
                              textInputAction: TextInputAction.next,
                              // 单行输入框里的长商品名会横向滚出视野、看不出被截；
                              // 允许折到两行，复查时能直接看到全名。
                              minLines: 1,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: '商品名称',
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '请填写商品名称';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: '金额（元）',
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
                            _FieldTile(
                              label: '消费日期',
                              value: _dateText,
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickDate,
                            ),
                            AppSelectField<int?>(
                              label: '平台',
                              value: _platformId,
                              options: <AppSelectOption<int?>>[
                                const AppSelectOption<int?>(
                                  value: null,
                                  label: '未分类',
                                ),
                                for (final NamedOption item in _platforms)
                                  AppSelectOption<int?>(
                                    value: item.id,
                                    label: item.name,
                                  ),
                              ],
                              onChanged: (int? value) =>
                                  setState(() => _platformId = value),
                            ),
                            AppSelectField<int?>(
                              label: '分类',
                              value: _categoryId,
                              options: <AppSelectOption<int?>>[
                                const AppSelectOption<int?>(
                                  value: null,
                                  label: '未分类',
                                ),
                                for (final _CategoryOption item in _categories)
                                  AppSelectOption<int?>(
                                    value: item.id,
                                    label: item.name,
                                  ),
                              ],
                              onChanged: (int? value) =>
                                  setState(() => _categoryId = value),
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
                            hintText: '可选，例如商户、用途',
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

/// 分类下拉项：保留网页端编辑分类时的关键词、排除词、优先级与兜底标记。
///
/// 后端 `PUT /finance/shopping/categories/{id}` 使用 `ShoppingCategoryCreate`
/// 全量覆盖；只传 name 会把关键词与优先级清空，因此编辑时必须原样回传。
class _CategoryOption {
  const _CategoryOption({
    required this.id,
    required this.name,
    required this.keywords,
    required this.exclude,
    required this.priority,
    required this.isFallback,
  });

  final int id;
  final String name;
  final List<String> keywords;
  final List<String> exclude;
  final int priority;
  final bool isFallback;

  factory _CategoryOption.fromJson(Map<String, dynamic> json) {
    return _CategoryOption(
      id: (json['id'] as num?)?.toInt() ?? -1,
      name: json['name'] as String? ?? '',
      keywords: ((json['keywords'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      exclude: ((json['exclude'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      isFallback: json['is_fallback'] as bool? ?? false,
    );
  }
}

/// 把金额转成不带多余尾零的输入文本（例如 12.50 → 12.5）。
String _plain(double value) {
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 只读字段行（日期），点击后交给上层弹选择器。
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
