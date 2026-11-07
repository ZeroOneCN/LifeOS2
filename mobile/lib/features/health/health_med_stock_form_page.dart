import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/health_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 药品库存新增 / 编辑：药品名称 + 低库存阈值。
///
/// 与网页端一致：库存数量由后端按「累计购入粒数 − 已服用粒数」推导，
/// 表单里的 `stock_qty` 固定回传 0、`unit` 固定回传「粒」；
/// 用户实际可维护的是药品名称与低库存阈值（`threshold`）。
/// 编辑走 PUT（全量覆盖），四个字段必须一起回传。
class HealthMedStockFormPage extends StatefulWidget {
  const HealthMedStockFormPage({super.key, this.stockId, this.initial});

  /// 为空表示新增药品库存；有值表示编辑。
  final int? stockId;

  /// 列表页快照；为空时按 [stockId] 拉取一次。
  final MedStock? initial;

  bool get isEdit => stockId != null;

  @override
  State<HealthMedStockFormPage> createState() => _HealthMedStockFormPageState();
}

class _HealthMedStockFormPageState extends State<HealthMedStockFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _threshold = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final MedStock? initial = widget.initial;
    if (initial != null) {
      _apply(initial);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _bootstrap();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    super.dispose();
  }

  /// 用快照预填编辑表单。
  void _apply(MedStock stock) {
    _name.text = stock.name;
    _threshold.text = _plain(stock.threshold);
  }

  /// 编辑模式下没有快照时，从库存列表里按 id 找回这一项。
  Future<void> _bootstrap() async {
    if (!widget.isEdit || widget.initial != null) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>('/health/medication/stocks'))
          .data;
      final List<MedStock> stocks =
          ((json?['items'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map item) =>
                  MedStock.fromJson(item.cast<String, dynamic>()))
              .toList();
      MedStock? target;
      for (final MedStock item in stocks) {
        if (item.id == widget.stockId) {
          target = item;
          break;
        }
      }
      if (target == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '库存记录不存在或已被删除',
        );
      }
      final MedStock found = target;
      if (!mounted) {
        return;
      }
      setState(() {
        _apply(found);
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

  /// 保存：新增 POST（按名称 upsert）/ 编辑 PUT 全量回传。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!scope.outbox.isOnline) {
      setState(() => _error = '当前无网络：保存药品库存需要联网，请恢复网络后重试');
      return;
    }
    final double? threshold =
        _threshold.text.trim().isEmpty ? null : double.parse(_threshold.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    final Map<String, dynamic> payload = <String, dynamic>{
      'medicine_name': _name.text.trim(),
      // 库存数量与单位由后端推导，按网页端口径固定回传。
      'stock_qty': 0,
      'threshold': threshold,
      'unit': '粒',
    };
    try {
      if (widget.isEdit) {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/health/medication/stocks/${widget.stockId}',
          data: payload,
        );
      } else {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/health/medication/stocks',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('已保存 ${_name.text.trim()} 的库存')),
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

  /// 删除库存：确认后删除，低库存提醒随之撤销。
  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除该药品库存？'),
          content: Text(
            '将删除「${_name.text.trim()}」的库存记录。\n'
            '该药品的低库存提醒会同步撤销，且无法恢复。',
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
          .delete<dynamic>('/health/medication/stocks/${widget.stockId}');
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('已删除该药品库存')));
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
    final bool busy = _loading || _saving || _deleting;
    return DetailPageScaffold(
      title: widget.isEdit ? '编辑药品库存' : '新增药品库存',
      bottomBar: widget.isEdit
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
          : SizedBox(
              height: kAppButtonHeight,
              width: double.infinity,
              child: AppPrimaryButton(
                label: '保存',
                loading: _saving,
                onPressed: busy ? null : _save,
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
                        title: '库存信息',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: <Widget>[
                            TextFormField(
                              controller: _name,
                              autofocus: !widget.isEdit,
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
                            TextFormField(
                              controller: _threshold,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: '低库存阈值',
                                suffixText: '粒',
                              ),
                              validator: (String? value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return null;
                                }
                                final double? parsed =
                                    double.tryParse(value!.trim());
                                if (parsed == null || parsed < 0) {
                                  return '请填不小于 0 的阈值';
                                }
                                return null;
                              },
                            ),
                            // helperText 会把输入框撑高，和上方名称输入框不等高；
                            // 说明文字单独一行，两个输入框保持同一高度。
                            Text(
                              '留空表示不提醒；余量低于该值时提醒。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '库存 = 累计购入粒数 − 已服用粒数，由购药与用药记录自动推导；'
                        '本页只维护药品名称与低库存阈值。',
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

/// 去掉无意义的尾零（20.0 → 20）。
String _plain(double value) {
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}
