import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/lifestyle_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 物品新增 / 编辑页的路由参数：[item] 为列表快照，[categories] 为统计里的分类可选值。
class LifestyleItemFormArgs {
  const LifestyleItemFormArgs({this.item, this.categories = const <String>[]});

  final LifestyleItem? item;
  final List<String> categories;
}

/// 物品录入 / 编辑：名称与分类必填，位置、价格、三个日期、状态、来源、备注可选。
///
/// 与网页端 `/lifestyle/items` 的 RecordManager 字段一致：
/// - 新增：`POST /lifestyle/items`，底部整行「保存」。
/// - 编辑：`PUT /lifestyle/items/{id}`，底部「左保存、右删除」，删除二次确认并说明统计影响。
/// - 状态、来源用 `AppSelectField`；分类选项来自 `GET /lifestyle/items/stats` 的 by_category。
/// - 日期留空提交 null：到期日为空的物品由列表侧判定不显示临期标记。
class LifestyleItemFormPage extends StatefulWidget {
  const LifestyleItemFormPage({
    super.key,
    this.recordId,
    this.initial,
    this.categories = const <String>[],
  });

  /// 编辑模式的物品 id；为空即新增。
  final int? recordId;

  /// 列表带进来的快照；为空时按 [recordId] 拉取。
  final LifestyleItem? initial;

  /// 现有分类（来自统计接口），用于分类下拉。
  final List<String> categories;

  @override
  State<LifestyleItemFormPage> createState() => _LifestyleItemFormPageState();
}

class _LifestyleItemFormPageState extends State<LifestyleItemFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _status = 'in_use';
  String _source = 'manual';

  /// 三个可选日期：购买 / 到期 / 结束。
  String? _purchaseDate;
  String? _expireDate;
  String? _endDate;

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.recordId != null;

  /// 分类下拉选项：预设分类 + 统计里的历史分类，去重后保持原顺序。
  List<String> get _categoryOptions {
    final List<String> options = List<String>.of(kItemCategories);
    for (final String category in widget.categories) {
      final String trimmed = category.trim();
      if (trimmed.isNotEmpty && !options.contains(trimmed)) {
        options.add(trimmed);
      }
    }
    final String current = _category.text.trim();
    if (current.isNotEmpty && !options.contains(current)) {
      options.insert(0, current);
    }
    return options;
  }

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final LifestyleItem? initial = widget.initial;
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
    _category.dispose();
    _location.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 用一条物品预填表单；历史未知状态/来源在下拉里补同名选项，避免编辑时丢失。
  void _apply(LifestyleItem item) {
    _name.text = item.itemName;
    _category.text = item.category;
    _location.text = item.location ?? '';
    _price.text = item.price == null ? '' : _plain(item.price!);
    _note.text = item.note ?? '';
    _status = item.status;
    _source = item.source;
    _purchaseDate = item.purchaseDate;
    _expireDate = item.expireDate;
    _endDate = item.endDate;
  }

  /// 编辑模式兜底：没有快照时按 id 取最新物品。
  Future<void> _loadRecord() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/lifestyle/items/${widget.recordId}',
          )).data;
      if (json == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '物品详情返回为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(LifestyleItem.fromJson(json));
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

  /// 数值去掉多余尾零，用于回填价格输入框。
  static String _plain(double value) {
    final String text = value.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// 逐级展示日期，留空返回 null；后端按 `date` 解析。
  static String? _dateOrNull(DateTime? value) {
    if (value == null) {
      return null;
    }
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  /// 选择某个可选日期。
  Future<void> _pickDate(String? current, ValueChanged<DateTime?> onPick) async {
    final DateTime initial = DateTime.tryParse(current ?? '') ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    onPick(picked);
  }

  /// 提交：新增走 POST、编辑走 PUT；失败保留输入便于修正。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_category.text.trim().isEmpty) {
      setState(() => _error = '请选择分类');
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.connectivity.isOnline) {
      setState(() => _error = '当前无网络：物品记录需要联网，请恢复网络后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final String priceText = _price.text.replaceAll(',', '').trim();
    final Map<String, dynamic> payload = <String, dynamic>{
      'item_name': _name.text.trim(),
      'category': _category.text.trim(),
      'location': _location.text.trim().isEmpty
          ? null
          : _location.text.trim(),
      'status': _status,
      'purchase_date': _purchaseDate,
      'price': priceText.isEmpty ? null : double.parse(priceText),
      'expire_date': _expireDate,
      'end_date': _endDate,
      'source': _source,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/lifestyle/items/${widget.recordId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/lifestyle/items',
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
            _editing
                ? '已保存「${_name.text.trim()}」'
                : '已添加「${_name.text.trim()}」',
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

  /// 删除：二次确认写明会影响总数 / 使用中 / 总价值 / 日均成本。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该物品？'),
          content: Text(
            '将删除「${_name.text.trim()}」。\n'
            '删除后物品总数、使用中数量、总价值与日均成本会同步回退，且无法恢复。',
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
        '/lifestyle/items/${widget.recordId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该物品')));
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
    final List<AppSelectOption<String>> statusOptions =
        <AppSelectOption<String>>[
          for (final ({String value, String label}) item in kItemStatuses)
            AppSelectOption<String>(value: item.value, label: item.label),
          if (!kItemStatuses.any(
            (({String value, String label}) item) => item.value == _status,
          ))
            AppSelectOption<String>(
              value: _status,
              label: itemStatusLabel(_status),
            ),
        ];
    final List<AppSelectOption<String>> sourceOptions =
        <AppSelectOption<String>>[
          for (final ({String value, String label}) item in kItemSources)
            AppSelectOption<String>(value: item.value, label: item.label),
          if (!kItemSources.any(
            (({String value, String label}) item) => item.value == _source,
          ))
            AppSelectOption<String>(value: _source, label: _source),
        ];

    return DetailPageScaffold(
      title: _editing ? '编辑物品' : '新增物品',
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
                        title: '基本信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: '物品名称（必填）',
                                hintText: '如：机械键盘、空气滤芯',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return '请输入物品名称';
                                }
                                return null;
                              },
                            ),
                            AppSelectField<String>(
                              label: '分类',
                              value: _category.text,
                              options: <AppSelectOption<String>>[
                                for (final String category in _categoryOptions)
                                  AppSelectOption<String>(
                                    value: category,
                                    label: category,
                                  ),
                              ],
                              hint: '请选择分类',
                              onChanged: (String value) =>
                                  setState(() => _category.text = value),
                            ),
                            AppSelectField<String>(
                              label: '状态',
                              value: _status,
                              options: statusOptions,
                              hint: '请选择状态',
                              onChanged: (String value) =>
                                  setState(() => _status = value),
                            ),
                            AppSelectField<String>(
                              label: '来源',
                              value: _source,
                              options: sourceOptions,
                              hint: '请选择来源',
                              onChanged: (String value) =>
                                  setState(() => _source = value),
                            ),
                            TextFormField(
                              controller: _location,
                              decoration: const InputDecoration(
                                labelText: '存放位置',
                                hintText: '—',
                                helperText: '如：书房抽屉、储物间',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                              textInputAction: TextInputAction.next,
                              validator: null,
                            ),
                            TextFormField(
                              controller: _price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: '价格',
                                hintText: '可不填',
                                prefixText: '¥ ',
                              ),
                              validator: (String? value) => _priceValidator(value),
                            ),
                            TextFormField(
                              controller: _note,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: '可选，例如型号、序列号、购买渠道',
                              ),
                            ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: '日期（可不填）',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            _DateField(
                              label: '购买日期',
                              value: _purchaseDate,
                              onTap: () => _pickDate(_purchaseDate, (date) {
                                setState(
                                  () => _purchaseDate = _dateOrNull(date),
                                );
                              }),
                              onClear: () => setState(() => _purchaseDate = null),
                            ),
                            _DateField(
                              label: '到期日期',
                              value: _expireDate,
                              onTap: () => _pickDate(_expireDate, (date) {
                                setState(() => _expireDate = _dateOrNull(date));
                              }),
                              onClear: () => setState(() => _expireDate = null),
                            ),
                            _DateField(
                              label: '结束日期',
                              value: _endDate,
                              onTap: () => _pickDate(_endDate, (date) {
                                setState(() => _endDate = _dateOrNull(date));
                              }),
                              onClear: () => setState(() => _endDate = null),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '到期日期留空时，列表不会显示临期或过期标记。',
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

  /// 价格可留空；填写时必须是不小于 0 的数字。
  String? _priceValidator(String? value) {
    final String text = (value ?? '').replaceAll(',', '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      return '请输入不小于 0 的价格';
    }
    return null;
  }
}

/// 可选日期行：未设置时显示「未设置」；已设置时右侧提供清除按钮。
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value ?? '未设置',
                style: value == null
                    ? theme.textTheme.bodyMedium?.copyWith(color: muted)
                    : null,
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 18, color: muted),
                ),
              ),
            Icon(Icons.calendar_today_outlined, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}
