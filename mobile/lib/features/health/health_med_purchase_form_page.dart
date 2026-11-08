import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 新增 / 编辑购药记录：购买日期、药品名称、渠道、数量、单位、每包装粒数、
/// 单价、总价、备注。
///
/// 后端 `POST /health/medication/purchases`（`MedPurchaseCreate`）与
/// `PUT /health/medication/purchases/{id}`：
/// `quantity > 0`、`unit_price >= 0`；`total_price` 留空时后端按
/// `quantity × unit_price` 自动计算。保存后后端会自动同步库存与低库存提醒。
class HealthMedPurchaseFormPage extends StatefulWidget {
  const HealthMedPurchaseFormPage({super.key, this.purchaseId, this.initial});

  /// 非空表示编辑模式。
  final int? purchaseId;

  /// 列表页带来的快照：可直接预填，缺失时按 id 拉取。
  final MedPurchase? initial;

  bool get isEditing => purchaseId != null;

  @override
  State<HealthMedPurchaseFormPage> createState() =>
      _HealthMedPurchaseFormPageState();
}

class _HealthMedPurchaseFormPageState
    extends State<HealthMedPurchaseFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _channel = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _unit = TextEditingController(text: '盒');
  final TextEditingController _pillsPerUnit = TextEditingController();
  final TextEditingController _unitPrice = TextEditingController();
  final TextEditingController _totalPrice = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final MedPurchase? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
    } else if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRecord();
        }
      });
    }
  }

  /// 用列表快照预填表单；空值保持空白，不写 0。
  void _apply(MedPurchase purchase) {
    _date = DateTime.tryParse(purchase.buyDate) ?? DateTime.now();
    _name.text = purchase.medicineName;
    _channel.text = purchase.channel ?? '';
    _quantity.text = _numberText(purchase.quantity);
    _unit.text = purchase.unit ?? '';
    _pillsPerUnit.text = purchase.pillsPerUnit == null
        ? ''
        : _numberText(purchase.pillsPerUnit!);
    _unitPrice.text = _numberText(purchase.unitPrice);
    _totalPrice.text =
        purchase.totalPrice == null ? '' : _numberText(purchase.totalPrice!);
    _note.text = purchase.note ?? '';
  }

  /// 数字转输入框文本：去掉无意义的小数尾零。
  String _numberText(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// 深链进入且无快照时按 id 拉取，失败时提示但仍可编辑。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/medication/purchases/${widget.purchaseId}',
              ))
          .data;
      if (!mounted || json == null) {
        return;
      }
      setState(() => _apply(MedPurchase.fromJson(json)));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _channel.dispose();
    _quantity.dispose();
    _unit.dispose();
    _pillsPerUnit.dispose();
    _unitPrice.dispose();
    _totalPrice.dispose();
    _note.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd`（后端 `buy_date` 口径）。
  String get _dateText {
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${_date.year}-${two(_date.month)}-${two(_date.day)}';
  }

  /// 选择购买日期。
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

  /// 提交购药记录；成功后返回 `true` 让列表刷新库存与购药列表。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(
        () => _error = widget.isEditing
            ? '当前无网络：编辑购药记录需要联网，请恢复网络后重试'
            : '当前无网络：新增购药记录需要联网，请恢复网络后重试',
      );
      return;
    }
    final double quantity = double.parse(_quantity.text.trim());
    final double unitPrice = double.parse(_unitPrice.text.trim());
    final double? pillsPerUnit = _pillsPerUnit.text.trim().isEmpty
        ? null
        : double.tryParse(_pillsPerUnit.text.trim());
    final double? totalPrice = _totalPrice.text.trim().isEmpty
        ? null
        : double.tryParse(_totalPrice.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'buy_date': _dateText,
      'medicine_name': _name.text.trim(),
      'channel': _channel.text.trim().isEmpty ? null : _channel.text.trim(),
      'unit': _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      'quantity': quantity,
      'pills_per_unit': pillsPerUnit,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (widget.isEditing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/medication/purchases/${widget.purchaseId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/medication/purchases',
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
            widget.isEditing
                ? '已更新 ${_name.text.trim()} 的购药记录'
                : '已记录 ${_name.text.trim()} 的购药',
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: widget.isEditing ? '编辑购药记录' : '新增购药记录',
      bottomBar: SizedBox(
        height: kAppButtonHeight,
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
                  title: '购药信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      TextFormField(
                        controller: _name,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '药品名称',
                          hintText: '例如：维生素D',
                        ),
                        validator: (String? value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请填写药品名称';
                          }
                          return null;
                        },
                      ),
                      _FieldTile(
                        label: '购买日期',
                        value: _dateText,
                        icon: Icons.calendar_today_outlined,
                        onTap: _pickDate,
                      ),
                      TextFormField(
                        controller: _channel,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '渠道',
                          hintText: '可选，例如：京东、线下药店',
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '数量与价格',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      Row(
                        spacing: 12,
                        children: <Widget>[
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: '数量',
                              ),
                              validator: (String? value) {
                                final double? parsed =
                                    double.tryParse((value ?? '').trim());
                                if (parsed == null || parsed <= 0) {
                                  return '数量须大于 0';
                                }
                                return null;
                              },
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _unit,
                              decoration: const InputDecoration(
                                labelText: '单位',
                                hintText: '盒',
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _pillsPerUnit,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          labelText: '每包装粒数',
                          suffixText: '粒',
                          hintText: '可选',
                        ),
                        validator: (String? value) {
                          if ((value ?? '').trim().isEmpty) {
                            return null;
                          }
                          final double? parsed = double.tryParse(value!.trim());
                          if (parsed == null || parsed < 0) {
                            return '请填不小于 0 的粒数';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _unitPrice,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          labelText: '单价（元）',
                          prefixText: '¥ ',
                          hintText: '0.00',
                        ),
                        validator: (String? value) {
                          final double? parsed =
                              double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 0) {
                            return '请填不小于 0 的单价';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _totalPrice,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          labelText: '总价（元）',
                          prefixText: '¥ ',
                          hintText: '留空则按 数量 × 单价 自动计算',
                        ),
                        validator: (String? value) {
                          if ((value ?? '').trim().isEmpty) {
                            return null;
                          }
                          final double? parsed = double.tryParse(value!.trim());
                          if (parsed == null || parsed < 0) {
                            return '请填不小于 0 的总价';
                          }
                          return null;
                        },
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
                      hintText: '可选，例如规格、批次',
                    ),
                  ),
                ),
                Text(
                  '保存后会自动计入对应药品库存，并重新判断低库存提醒。',
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
