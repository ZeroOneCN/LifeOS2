import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 体检指标批量录入（**按模板填写**）。
///
/// 流程与网页端「批量录入」一致：
/// 1. 先选组合模板（套餐，如血常规）或单个指标模板，一次带入多个指标项；
/// 2. 每个指标项带出单位与参考范围，只需填数值；
/// 3. 数值为空的行不提交，避免写入无意义的空记录。
///
/// 后端没有批量接口，逐条 `POST /health/checkup`，与网页端行为一致。
/// 全部成功后返回 `true` 触发列表刷新；任一条失败则保留页面并提示。
class HealthCheckupBulkPage extends StatefulWidget {
  const HealthCheckupBulkPage({super.key});

  @override
  State<HealthCheckupBulkPage> createState() => _HealthCheckupBulkPageState();
}

class _HealthCheckupBulkPageState extends State<HealthCheckupBulkPage> {
  final List<_PanelOption> _panels = <_PanelOption>[];
  final List<_RowDraft> _rows = <_RowDraft>[];

  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadOptions();
      }
    });
  }

  @override
  void dispose() {
    for (final _RowDraft row in _rows) {
      for (final TextEditingController controller in row.controllers) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  /// 并行拉组合模板（含内置套餐）与单指标模板，失败时降级为「自由填写」。
  Future<void> _loadOptions() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          scope.apiClient
              .get<List<dynamic>>('/health/checkup/panels')
              .then((value) => value.data)
              .catchError((Object _) => const <dynamic>[]),
          scope.apiClient
              .get<List<dynamic>>('/health/checkup/panels/presets')
              .then((value) => value.data)
              .catchError((Object _) => const <dynamic>[]),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/checkup/templates',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data)
              .catchError((Object _) => null),
        ],
      );
      if (!mounted) {
        return;
      }
      final List<_PanelOption> options = <_PanelOption>[];
      for (final Object? item in (responses[0] as List<dynamic>?) ??
          const <dynamic>[]) {
        if (item is Map) {
          options.add(_PanelOption.fromJson(item.cast<String, dynamic>(), builtIn: false));
        }
      }
      for (final Object? item in (responses[1] as List<dynamic>?) ??
          const <dynamic>[]) {
        if (item is Map) {
          options.add(_PanelOption.fromJson(item.cast<String, dynamic>(), builtIn: true));
        }
      }
      // 单指标模板作为「只有一项」的组合，统一走同一套选择器。
      final Map<String, dynamic>? templateJson =
          responses[2] as Map<String, dynamic>?;
      for (final Object? item
          in (templateJson?['items'] as List<dynamic>?) ?? const <dynamic>[]) {
        if (item is Map) {
          final Map<String, dynamic> map = item.cast<String, dynamic>();
          options.add(
            _PanelOption(
              name: map['item_name'] as String? ?? '',
              builtIn: false,
              items: <_TemplateItem>[_TemplateItem.fromJson(map)],
              isSingle: true,
            ),
          );
        }
      }
      setState(() {
        _panels
          ..clear()
          ..addAll(options);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '模板加载失败：${error.message}';
      });
    }
  }

  /// 选模板后整批追加指标行；已存在的同名指标不重复添加。
  void _applyPanel(_PanelOption option) {
    setState(() {
      for (final _TemplateItem item in option.items) {
        final bool exists = _rows.any((_RowDraft row) =>
            row.itemName.text.trim() == item.itemName.trim());
        if (exists) {
          continue;
        }
        _rows.add(_RowDraft.fromTemplate(item));
      }
    });
  }

  /// 添加一行空白指标（模板里没有覆盖到的项）。
  void _addBlankRow() {
    setState(() {
      _rows.add(_RowDraft.fromTemplate(const _TemplateItem(itemName: '')));
    });
  }

  Future<void> _pickTemplate() async {
    if (_panels.isEmpty) {
      _addBlankRow();
      return;
    }
    final _PanelOption? picked = await showModalBottomSheet<_PanelOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '选择模板（套餐一次带入多项）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final _PanelOption option in _panels)
                ListTile(
                  title: Text(
                    option.isSingle
                        ? option.name
                        : '${option.builtIn ? '[内置] ' : ''}${option.name}',
                  ),
                  subtitle: Text(
                    option.isSingle
                        ? '单指标模板 · 带入 1 项'
                        : '组合模板 · 带入 ${option.items.length} 项',
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      _applyPanel(picked);
    }
  }

  /// 逐条提交；只有全部成功才关闭页面。
  Future<void> _save() async {
    final List<_RowDraft> valid = _rows
        .where((_RowDraft row) =>
            row.itemName.text.trim().isNotEmpty && row.value.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      setState(() => _error = '至少填写一项指标数值');
      return;
    }
    // 逐行做数值校验，避免半途失败。
    for (final _RowDraft row in valid) {
      if (double.tryParse(row.value.text.trim()) == null) {
        setState(() => _error = '「${row.itemName.text.trim()}」的数值不是有效数字');
        return;
      }
    }
    final AppScope scope = AppScope.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final String date = _dateText(_date);
    int done = 0;
    try {
      for (final _RowDraft row in valid) {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/checkup',
          data: <String, dynamic>{
            'check_date': date,
            'item_name': row.itemName.text.trim(),
            'value': double.parse(row.value.text.trim()),
            'unit': _nullable(row.unit.text),
            'ref_low': row.refLow,
            'ref_high': row.refHigh,
            'reference_range': _nullable(row.referenceRange.text),
          },
        );
        done += 1;
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = done == 0
            ? '保存失败：${error.message}'
            : '已保存 $done 项，「${valid[done].itemName.text.trim()}」失败：${error.message}';
      });
    }
  }

  /// 空串一律提交 null，不写 0。
  String? _nullable(String raw) {
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// `yyyy-MM-dd`。
  String _dateText(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '新增体检记录',
      bottomBar: AppPrimaryButton(
        label: _saving ? '保存中…' : '保存全部指标',
        onPressed: _saving ? null : _save,
      ),
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              SectionCard(
                title: '检查日期',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _saving ? null : _pickDate,
                  child: InputDecorator(
                    isEmpty: false,
                    decoration: const InputDecoration(
                      labelText: '检查日期',
                      contentPadding: EdgeInsets.fromLTRB(12, 16, 8, 16),
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                    ),
                    child: Text(_dateText(_date)),
                  ),
                ),
              ),
              SectionCard(
                title: '指标项（按模板填写）',
                trailing: AppPrimaryAction(
                  label: '选模板',
                  onPressed: _saving ? () {} : _pickTemplate,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: <Widget>[
                    if (_rows.isEmpty)
                      Text(
                        '先点右上「选模板」带入体检套餐，或点下方「添加空白指标」手动填写。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      for (int i = 0; i < _rows.length; i++)
                        _RowEditor(
                          row: _rows[i],
                          onRemove: () => setState(() {
                            _rows.removeAt(i).dispose();
                          }),
                        ),
                    AppSecondaryButton(
                      label: '添加空白指标',
                      icon: Icons.add,
                      onPressed: _saving ? null : _addBlankRow,
                    ),
                  ],
                ),
              ),
              Text(
                '数值为空的行不会提交；状态由后端按参考上下限自动判断。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 模板选项：组合模板（套餐）、内置套餐、或单指标模板。
class _PanelOption {
  _PanelOption({
    required this.name,
    required this.items,
    required this.builtIn,
    this.isSingle = false,
  });

  factory _PanelOption.fromJson(
    Map<String, dynamic> json, {
    required bool builtIn,
  }) {
    return _PanelOption(
      name: json['panel_name'] as String? ?? '',
      builtIn: builtIn,
      items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map item) =>
              _TemplateItem.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }

  final String name;
  final List<_TemplateItem> items;
  final bool builtIn;
  final bool isSingle;
}

/// 模板里的一个指标项。
class _TemplateItem {
  const _TemplateItem({
    required this.itemName,
    this.unit,
    this.refLow,
    this.refHigh,
    this.referenceRange,
  });

  factory _TemplateItem.fromJson(Map<String, dynamic> json) {
    return _TemplateItem(
      itemName: json['item_name'] as String? ?? '',
      unit: json['unit'] as String?,
      refLow: (json['ref_low'] as num?)?.toDouble(),
      refHigh: (json['ref_high'] as num?)?.toDouble(),
      referenceRange: json['reference_range'] as String?,
    );
  }

  final String itemName;
  final String? unit;
  final double? refLow;
  final double? refHigh;
  final String? referenceRange;
}

/// 一行可编辑指标：名称、数值、单位与参考范围。
class _RowDraft {
  _RowDraft({
    required this.itemName,
    required this.value,
    required this.unit,
    required this.referenceRange,
    this.refLow,
    this.refHigh,
  });

  factory _RowDraft.fromTemplate(_TemplateItem item) {
    return _RowDraft(
      itemName: TextEditingController(text: item.itemName),
      value: TextEditingController(),
      unit: TextEditingController(text: item.unit ?? ''),
      referenceRange: TextEditingController(text: item.referenceRange ?? ''),
      refLow: item.refLow,
      refHigh: item.refHigh,
    );
  }

  final TextEditingController itemName;
  final TextEditingController value;
  final TextEditingController unit;
  final TextEditingController referenceRange;
  final double? refLow;
  final double? refHigh;

  List<TextEditingController> get controllers =>
      <TextEditingController>[itemName, value, unit, referenceRange];

  void dispose() {
    for (final TextEditingController controller in controllers) {
      controller.dispose();
    }
  }

  /// 参考范围文案：优先参考区间，其次上下限拼接；都没有则不显示。
  String? get rangeText {
    final String range = referenceRange.text.trim();
    if (range.isNotEmpty) {
      return range;
    }
    if (refLow == null && refHigh == null) {
      return null;
    }
    if (refLow != null && refHigh != null) {
      return '${_plain(refLow!)}–${_plain(refHigh!)}';
    }
    if (refLow != null) {
      return '≥ ${_plain(refLow!)}';
    }
    return '≤ ${_plain(refHigh!)}';
  }
}

/// 数字去尾零。
String _plain(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// 单行编辑块：名称 + 数值 + 单位/参考范围提示 + 删除。
class _RowEditor extends StatelessWidget {
  const _RowEditor({required this.row, required this.onRemove});

  final _RowDraft row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? range = row.rangeText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: <Widget>[
            Expanded(
              child: TextFormField(
                controller: row.itemName,
                decoration: const InputDecoration(
                  labelText: '指标名称',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: TextFormField(
                controller: row.value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: '数值',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: '移除该指标',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Row(
          spacing: 8,
          children: <Widget>[
            SizedBox(
              width: 96,
              child: TextFormField(
                controller: row.unit,
                decoration: const InputDecoration(
                  labelText: '单位',
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: Text(
                range == null ? '参考范围：—' : '参考范围：$range',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
