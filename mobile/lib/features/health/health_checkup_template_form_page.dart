import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 单指标模板新增 / 编辑。
///
/// 字段与后端 `CheckupTemplateCreate` 一致：指标名（必填）、类别、单位、
/// 参考下限、参考上限；后端没有参考范围文本框（参考范围由上下限推导）。
///
/// - 新增 `POST /health/checkup/templates`；编辑 `PUT /health/checkup/templates/{id}`；
/// - 删除 `DELETE /health/checkup/templates/{id}`（仅编辑态可见，二次确认写明影响）。
class HealthCheckupTemplateFormPage extends StatefulWidget {
  const HealthCheckupTemplateFormPage({
    super.key,
    this.templateId,
    this.initial,
  });

  /// 编辑的模板 id；为空即新增。
  final int? templateId;

  /// 列表带进来的快照，打开即预填；缺失时按 id 拉取。
  final Map<String, dynamic>? initial;

  @override
  State<HealthCheckupTemplateFormPage> createState() =>
      _HealthCheckupTemplateFormPageState();
}

class _HealthCheckupTemplateFormPageState
    extends State<HealthCheckupTemplateFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _itemName = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _unit = TextEditingController();
  final TextEditingController _refLow = TextEditingController();
  final TextEditingController _refHigh = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.templateId != null;

  @override
  void initState() {
    super.initState();
    if (!_editing) {
      return;
    }
    final Map<String, dynamic>? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
    } else {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadTemplate();
        }
      });
    }
  }

  @override
  void dispose() {
    _itemName.dispose();
    _category.dispose();
    _unit.dispose();
    _refLow.dispose();
    _refHigh.dispose();
    super.dispose();
  }

  /// 快照预填：空值留空，不写 0。
  void _apply(Map<String, dynamic> template) {
    _itemName.text = template['item_name'] as String? ?? '';
    _category.text = template['category'] as String? ?? '';
    _unit.text = template['unit'] as String? ?? '';
    _refLow.text = _plain((template['ref_low'] as num?)?.toDouble());
    _refHigh.text = _plain((template['ref_high'] as num?)?.toDouble());
  }

  /// 无快照时按 id 拉取；模板接口是分页结构，这里用 100 条内本地匹配。
  Future<void> _loadTemplate() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json =
          (await scope.apiClient.get<Map<String, dynamic>>(
            '/health/checkup/templates',
            queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
          )).data;
      final List<dynamic> items =
          (json?['items'] as List<dynamic>?) ?? const <dynamic>[];
      final Map<String, dynamic>? matched = items
          .whereType<Map>()
          .map((Map item) => item.cast<String, dynamic>())
          .where((Map<String, dynamic> item) => item['id'] == widget.templateId)
          .firstOrNull;
      if (matched == null) {
        throw const ApiException(
          kind: ApiErrorKind.notFound,
          message: '模板不存在或已被删除',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(matched);
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

  /// 保存：新增 POST、编辑 PUT；失败保留输入。
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
      'item_name': _itemName.text.trim(),
      'category': _optionalText(_category),
      'unit': _optionalText(_unit),
      'ref_low': _optionalDouble(_refLow),
      'ref_high': _optionalDouble(_refHigh),
    };
    try {
      if (_editing) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/checkup/templates/${widget.templateId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/checkup/templates',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? '已更新指标模板' : '已新增指标模板')),
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

  /// 删除模板：二次确认说明只影响录入选项。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除该指标模板？'),
          content: Text(
            '将删除「${_itemName.text.trim()}」。\n'
            '模板只用于「按模板录入」时带入指标，删除后已保存的体检记录不受影响。',
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
        '/health/checkup/templates/${widget.templateId}',
      );
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该指标模板')));
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
      title: _editing ? '编辑指标模板' : '新增指标模板',
      bottomBar: _loading
          ? null
          : Column(
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
                  '模板不会写入体检记录；删除模板不影响历史记录。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: <Widget>[
                      SectionCard(
                        title: _editing ? '修改指标模板' : '指标模板',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _itemName,
                              autofocus: !_editing,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '指标名（必填）',
                                hintText: '例如 空腹血糖',
                              ),
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return '请填写指标名';
                                }
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _category,
                              decoration: const InputDecoration(
                                labelText: '类别（可选）',
                                hintText: '例如 血常规 / 肝肾功能',
                              ),
                            ),
                            TextFormField(
                              controller: _unit,
                              decoration: const InputDecoration(
                                labelText: '单位（可选）',
                                hintText: '例如 mmol/L',
                              ),
                            ),
                            TextFormField(
                              controller: _refLow,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '参考下限（可选）',
                                hintText: '例如 3.9',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '参考下限'),
                            ),
                            TextFormField(
                              controller: _refHigh,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '参考上限（可选）',
                                hintText: '例如 6.1',
                              ),
                              validator: (String? value) =>
                                  _validateDouble(value, '参考上限'),
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

  /// 可空小数校验：留空合法；填写必须是合法非负数字。
  String? _validateDouble(String? value, String label) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return '$label 请填数字';
    }
    if (parsed < 0) {
      return '$label 不能为负';
    }
    return null;
  }

  /// `5.60` → `5.6`；null → 空串。
  String _plain(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
