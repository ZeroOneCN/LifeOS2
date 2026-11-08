import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 体检组合模板（套餐）新增 / 编辑。
///
/// 后端契约 `CheckupPanelCreate`：`panel_name`、`note`、`items[]`，
/// 每个指标项含 `item_name` / `unit` / `ref_low` / `ref_high`；
/// `reference_range` 由后端按上下限自动生成，移动端不提交也不展示输入框。
///
/// - 新增 `POST /health/checkup/panels`；编辑 `PUT /health/checkup/panels/{id}`
///   （后端重建明细，以本次提交为准）；
/// - 删除 `DELETE /health/checkup/panels/{id}`（仅编辑态可见，二次确认写明影响）。
///
/// 指标顺序口径：后端按 `item_name` 升序返回，不支持手工排序，本页不提供拖动。
class HealthCheckupPanelFormPage extends StatefulWidget {
  const HealthCheckupPanelFormPage({super.key, this.panelId, this.initial});

  /// 编辑的组合 id；为空即新增。
  final int? panelId;

  /// 列表带进来的快照（含 items），打开即预填。
  final Map<String, dynamic>? initial;

  @override
  State<HealthCheckupPanelFormPage> createState() =>
      _HealthCheckupPanelFormPageState();
}

class _HealthCheckupPanelFormPageState
    extends State<HealthCheckupPanelFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _panelName = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_PanelItemDraft> _items = <_PanelItemDraft>[];

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.panelId != null;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
    }
    if (_items.isEmpty) {
      _items.add(_PanelItemDraft.empty());
    }
  }

  @override
  void dispose() {
    _panelName.dispose();
    _note.dispose();
    for (final _PanelItemDraft item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  /// 用组合快照预填：名称、说明与全部指标项。
  void _apply(Map<String, dynamic> panel) {
    _panelName.text = panel['panel_name'] as String? ?? '';
    _note.text = panel['note'] as String? ?? '';
    final List<dynamic> items =
        (panel['items'] as List<dynamic>?) ?? const <dynamic>[];
    for (final Object? raw in items) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> map = raw.cast<String, dynamic>();
      _items.add(
        _PanelItemDraft(
          itemName: TextEditingController(
            text: map['item_name'] as String? ?? '',
          ),
          unit: TextEditingController(text: map['unit'] as String? ?? ''),
          refLow: TextEditingController(
            text: _plain((map['ref_low'] as num?)?.toDouble()),
          ),
          refHigh: TextEditingController(
            text: _plain((map['ref_high'] as num?)?.toDouble()),
          ),
        ),
      );
    }
  }

  /// 新增一行空白指标。
  void _addItem() {
    setState(() => _items.add(_PanelItemDraft.empty()));
  }

  /// 移除指定行；保留至少一行，避免空表单。
  void _removeItem(int index) {
    if (_items.length <= 1) {
      setState(() => _items.first.clear());
      return;
    }
    setState(() {
      _items.removeAt(index).dispose();
    });
  }

  /// 可空小数：留空提交 null。
  double? _optionalDouble(TextEditingController controller) {
    final String text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// 可空文本：全空白按未填处理。
  String? _optionalText(TextEditingController controller) {
    final String text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// 保存：先校验组合名与指标项，再按新增 / 编辑分流。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // 只提交填了指标名的行；空白行不提交，避免写入空指标。
    final List<_PanelItemDraft> valid = _items
        .where((_PanelItemDraft item) => item.itemName.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      setState(() => _error = '至少填写一项指标名');
      return;
    }
    final Set<String> names = <String>{};
    for (final _PanelItemDraft item in valid) {
      final String name = item.itemName.text.trim();
      if (!names.add(name)) {
        setState(() => _error = '指标「$name」重复，请合并或改名');
        return;
      }
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'panel_name': _panelName.text.trim(),
      'note': _optionalText(_note),
      'items': <Map<String, dynamic>>[
        for (final _PanelItemDraft item in valid)
          <String, dynamic>{
            'item_name': item.itemName.text.trim(),
            'unit': _optionalText(item.unit),
            'ref_low': _optionalDouble(item.refLow),
            'ref_high': _optionalDouble(item.refHigh),
          },
      ],
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/checkup/panels/${widget.panelId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/checkup/panels',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? '已更新组合模板' : '已新建组合模板')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = describeWriteFailure(error);
      });
    }
  }

  /// 删除组合：二次确认说明只影响录入选项。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除该组合模板？'),
          content: Text(
            '将删除「${_panelName.text.trim()}」及其全部指标项。\n'
            '组合只用于「按模板录入」时批量带入指标，删除后已保存的体检记录不受影响。',
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
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await scope.apiClient.delete<dynamic>(
        '/health/checkup/panels/${widget.panelId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该组合模板')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _error = describeWriteFailure(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: _editing ? '编辑组合模板' : '新建组合模板',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
          const SizedBox(height: 6),
          Text(
            '保存后组合内的指标项以本次提交为准；删除组合不影响历史体检记录。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: <Widget>[
                SectionCard(
                  title: '组合信息',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      TextFormField(
                        controller: _panelName,
                        autofocus: !_editing,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '组合名称（必填）',
                          hintText: '例如 年度体检套餐',
                        ),
                        validator: (String? value) {
                          if ((value ?? '').trim().isEmpty) {
                            return '请填写组合名称';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _note,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '说明（可选）',
                          hintText: '例如 每年一次的基础套餐',
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '指标项（${_items.length}）',
                  trailing: AppPrimaryAction(
                    label: '添加指标',
                    onPressed: _addItem,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      for (int i = 0; i < _items.length; i++)
                        _PanelItemEditor(
                          key: ObjectKey(_items[i]),
                          draft: _items[i],
                          removable: _items.length > 1,
                          onRemove: () => _removeItem(i),
                        ),
                      Text(
                        '参考范围由后端按上下限自动生成；至少填写一项指标名。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
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

  /// `5.60` → `5.6`；null → 空串。
  String _plain(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// 组合内一项指标的可编辑草稿。
class _PanelItemDraft {
  _PanelItemDraft({
    required this.itemName,
    required this.unit,
    required this.refLow,
    required this.refHigh,
  });

  /// 空白行：四个输入框全空。
  factory _PanelItemDraft.empty() {
    return _PanelItemDraft(
      itemName: TextEditingController(),
      unit: TextEditingController(),
      refLow: TextEditingController(),
      refHigh: TextEditingController(),
    );
  }

  final TextEditingController itemName;
  final TextEditingController unit;
  final TextEditingController refLow;
  final TextEditingController refHigh;

  /// 清空当前行（保留最后一行时使用）。
  void clear() {
    itemName.clear();
    unit.clear();
    refLow.clear();
    refHigh.clear();
  }

  void dispose() {
    itemName.dispose();
    unit.dispose();
    refLow.dispose();
    refHigh.dispose();
  }
}

/// 单项指标编辑块：指标名 + 单位 + 参考上下限 + 移除。
class _PanelItemEditor extends StatelessWidget {
  const _PanelItemEditor({
    super.key,
    required this.draft,
    required this.removable,
    required this.onRemove,
  });

  final _PanelItemDraft draft;
  final bool removable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: draft.itemName,
                  decoration: const InputDecoration(
                    labelText: '指标名',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: TextFormField(
                  controller: draft.unit,
                  decoration: const InputDecoration(
                    labelText: '单位',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: removable ? '移除该指标' : '清空该指标',
                onPressed: onRemove,
                icon: Icon(
                  removable ? Icons.delete_outline : Icons.backspace_outlined,
                ),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: draft.refLow,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '参考下限',
                    isDense: true,
                  ),
                  validator: (String? value) => _validateDouble(value),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: draft.refHigh,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '参考上限',
                    isDense: true,
                  ),
                  validator: (String? value) => _validateDouble(value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 留空合法；填写必须是合法非负数字。
  String? _validateDouble(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return '请填数字';
    }
    if (parsed < 0) {
      return '不能为负';
    }
    return null;
  }
}
