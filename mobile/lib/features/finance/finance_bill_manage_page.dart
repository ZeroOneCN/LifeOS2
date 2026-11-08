import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 账单字典维护的三种类型。
enum BillManageKind { loanPlatform, rentChannel, subscriptionCategory }

/// 账单管理配套字典维护页。
///
/// 对应后端标准 CRUD：
/// - 网贷平台 `/finance/loan-platforms`
/// - 租房渠道 `/finance/rent-channels`
/// - 订阅分类 `/finance/subscription-categories`
///
/// 删除字典不会删除已落库的业务记录，只影响后续新增时的可选项。
class FinanceBillManagePage extends StatefulWidget {
  const FinanceBillManagePage({super.key, required this.kind});

  final BillManageKind kind;

  @override
  State<FinanceBillManagePage> createState() => _FinanceBillManagePageState();
}

class _FinanceBillManagePageState extends State<FinanceBillManagePage> {
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 字典接口路径。
  String get _path {
    switch (widget.kind) {
      case BillManageKind.loanPlatform:
        return '/finance/loan-platforms';
      case BillManageKind.rentChannel:
        return '/finance/rent-channels';
      case BillManageKind.subscriptionCategory:
        return '/finance/subscription-categories';
    }
  }

  /// 页面标题。
  String get _title {
    switch (widget.kind) {
      case BillManageKind.loanPlatform:
        return '网贷平台';
      case BillManageKind.rentChannel:
        return '租房渠道';
      case BillManageKind.subscriptionCategory:
        return '订阅分类';
    }
  }

  /// 新增按钮文案。
  String get _addLabel {
    switch (widget.kind) {
      case BillManageKind.loanPlatform:
        return '新增平台';
      case BillManageKind.rentChannel:
        return '新增渠道';
      case BillManageKind.subscriptionCategory:
        return '新增分类';
    }
  }

  /// 删除确认中的影响说明。
  String get _deleteImpact {
    switch (widget.kind) {
      case BillManageKind.loanPlatform:
        return '历史网贷账单不会删除，但对应账单将失去平台名称。';
      case BillManageKind.rentChannel:
        return '已有住房记录仍保留原渠道文本，仅后续新增时不再出现该选项。';
      case BillManageKind.subscriptionCategory:
        return '已保存的订阅仍保留原分类文本，仅后续新增时不再出现该选项。';
    }
  }

  /// 拉取字典列表。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic>? json = (await scope.apiClient
              .get<Map<String, dynamic>>(
                _path,
                queryParameters: <String, dynamic>{
                  'page': 1,
                  'page_size': 100,
                },
              ))
          .data;
      if (!mounted) {
        return;
      }
      setState(() {
        _items = ((json?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) => item.cast<String, dynamic>())
            .toList(growable: false);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    }
  }

  /// 保存一条字典：id 为空 POST，否则 PUT。
  Future<void> _save(
    Map<String, dynamic>? existing,
    Map<String, dynamic> payload,
  ) async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      if (existing == null) {
        await scope.apiClient.post<Map<String, dynamic>>(
          _path,
          data: payload,
        );
      } else {
        await scope.apiClient.put<Map<String, dynamic>>(
          '$_path/${(existing['id'] as num?)?.toInt()}',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(existing == null ? '已新增$_title' : '已更新$_title')),
      );
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('保存失败：${error.message}')));
      }
    }
  }

  /// 删除一条字典：二次确认并写明影响。
  Future<void> _delete(Map<String, dynamic> item) async {
    final String name = item['name'] as String? ?? '';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('删除「$name」？'),
          content: Text('$_deleteImpact\n删除后无法恢复。'),
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await scope.apiClient.delete<dynamic>(
        '$_path/${(item['id'] as num?)?.toInt()}',
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('已删除「$name」')));
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('删除失败：${error.message}')));
      }
    }
  }

  /// 打开新增 / 编辑表单。
  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final Map<String, dynamic>? payload =
        widget.kind == BillManageKind.loanPlatform
            ? await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (BuildContext context) =>
                    _LoanPlatformDialog(initial: item),
              )
            : await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (BuildContext context) => _NameDialog(
                  title: item == null ? _addLabel : '编辑$_title',
                  label: '名称',
                  initial: item?['name'] as String? ?? '',
                ),
              );
    if (payload == null || !mounted) {
      return;
    }
    await _save(item, payload);
  }

  /// 平台副标题：账单日 / 还款日 / 额度。
  String _platformSubtitle(Map<String, dynamic> item) {
    final List<String> parts = <String>[];
    final int? billDay = (item['bill_day'] as num?)?.toInt();
    final int? dueDay = (item['due_day'] as num?)?.toInt();
    final double? limit = (item['credit_limit'] as num?)?.toDouble();
    if (billDay != null) {
      parts.add('账单日 $billDay 日');
    }
    if (dueDay != null) {
      parts.add('还款日 $dueDay 日');
    }
    if (limit != null) {
      parts.add('额度 ${_money(limit)}');
    }
    return parts.join(' · ');
  }

  /// 金额格式：整数不带小数，其余保留两位。
  String _money(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: _title,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              spacing: 8,
              children: <Widget>[
                Text('加载失败：$_error', textAlign: TextAlign.center),
                TextButton(onPressed: _refresh, child: const Text('重试')),
              ],
            )
          else
            SectionCard(
              title: _title,
              trailing: AppPrimaryAction(
                label: _addLabel,
                onPressed: () => _openForm(),
              ),
              child: _items.isEmpty
                  ? Text(
                      '暂无$_title，点右上角「$_addLabel」创建',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      spacing: 4,
                      children: <Widget>[
                        for (final Map<String, dynamic> item in _items)
                          Row(
                            spacing: 8,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      item['name'] as String? ?? '未命名',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    if (widget.kind ==
                                            BillManageKind.loanPlatform &&
                                        _platformSubtitle(item).isNotEmpty)
                                      Text(
                                        _platformSubtitle(item),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '更多操作',
                                padding: EdgeInsets.zero,
                                onSelected: (String value) {
                                  if (value == 'edit') {
                                    _openForm(item);
                                  } else {
                                    _delete(item);
                                  }
                                },
                                itemBuilder: (BuildContext context) =>
                                    const <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// 网贷平台表单：名称、账单日、还款日、额度、容时与违约金、备注。
class _LoanPlatformDialog extends StatefulWidget {
  const _LoanPlatformDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_LoanPlatformDialog> createState() => _LoanPlatformDialogState();
}

class _LoanPlatformDialogState extends State<_LoanPlatformDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _billDay = TextEditingController();
  final TextEditingController _dueDay = TextEditingController();
  final TextEditingController _creditLimit = TextEditingController();
  final TextEditingController _graceDays = TextEditingController();
  final TextEditingController _graceHour = TextEditingController();
  final TextEditingController _penaltyRate = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _graceAuto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? initial = widget.initial;
    if (initial == null) {
      _graceDays.text = '3';
      _graceHour.text = '0';
      _penaltyRate.text = '0';
      return;
    }
    _name.text = initial['name'] as String? ?? '';
    _billDay.text = _intText(initial['bill_day']);
    _dueDay.text = _intText(initial['due_day']);
    _creditLimit.text = _numberText(initial['credit_limit']);
    _graceDays.text = _intText(initial['grace_days']);
    _graceHour.text = _intText(initial['grace_hour']);
    _penaltyRate.text = _numberText(initial['penalty_rate']);
    _graceAuto = initial['grace_auto'] as bool? ?? false;
    _note.text = initial['note'] as String? ?? '';
  }

  /// 整数转文本：null 保持空串。
  String _intText(Object? value) {
    final int? number = (value as num?)?.toInt();
    return number == null ? '' : '$number';
  }

  /// 数字转文本：null 保持空串，去掉无意义小数。
  String _numberText(Object? value) {
    final double? number = (value as num?)?.toDouble();
    if (number == null) {
      return '';
    }
    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : '$number';
  }

  @override
  void dispose() {
    _name.dispose();
    _billDay.dispose();
    _dueDay.dispose();
    _creditLimit.dispose();
    _graceDays.dispose();
    _graceHour.dispose();
    _penaltyRate.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 解析可空整数并校验范围。
  int? _parseInt(
    String value,
    String label, {
    required int min,
    required int max,
  }) {
    final String text = value.trim();
    if (text.isEmpty) {
      return null;
    }
    final int? parsed = int.tryParse(text);
    if (parsed == null || parsed < min || parsed > max) {
      throw FormatException('$label需在 $min-$max 之间');
    }
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增网贷平台' : '编辑网贷平台'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: <Widget>[
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '平台名称'),
            ),
            Row(
              spacing: 10,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _billDay,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '账单日',
                      hintText: '1-31',
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _dueDay,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '还款日',
                      hintText: '1-31',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _creditLimit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '授信额度（可选）'),
            ),
            Row(
              spacing: 10,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _graceDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '容时天数',
                      hintText: '0-15',
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _graceHour,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '截止小时',
                      hintText: '0-23',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _penaltyRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '违约金费率（%/天）',
                hintText: '0.05 表示每日 0.05%',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('容时自动生效'),
              value: _graceAuto,
              onChanged: (bool value) => setState(() => _graceAuto = value),
            ),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        AppActionRow(
          first: AppSecondaryButton(
            label: '取消',
            compact: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          second: AppPrimaryButton(
            label: '保存',
            compact: true,
            onPressed: () {
              final String name = _name.text.trim();
              if (name.isEmpty) {
                setState(() => _error = '请填写平台名称');
                return;
              }
              try {
                final int graceDays =
                    _parseInt(_graceDays.text, '容时天数', min: 0, max: 15) ?? 3;
                final int graceHour =
                    _parseInt(_graceHour.text, '截止小时', min: 0, max: 23) ?? 0;
                final String limitText = _creditLimit.text.trim();
                final double? limit =
                    limitText.isEmpty ? null : double.tryParse(limitText);
                if (limitText.isNotEmpty && (limit == null || limit < 0)) {
                  throw const FormatException('授信额度需不小于 0');
                }
                final double penalty =
                    double.tryParse(_penaltyRate.text.trim()) ?? 0;
                if (penalty < 0 || penalty > 5) {
                  throw const FormatException('违约金费率需在 0-5 之间');
                }
                Navigator.of(context).pop(<String, dynamic>{
                  'name': name,
                  'bill_day': _parseInt(_billDay.text, '账单日', min: 1, max: 31),
                  'due_day': _parseInt(_dueDay.text, '还款日', min: 1, max: 31),
                  'credit_limit': limit,
                  'grace_days': graceDays,
                  'grace_auto': _graceAuto,
                  'grace_hour': graceHour,
                  'penalty_rate': penalty,
                  'note': _note.text.trim().isEmpty
                      ? null
                      : _note.text.trim(),
                });
              } on FormatException catch (error) {
                setState(() => _error = error.message);
              }
            },
          ),
        ),
      ],
    );
  }
}

/// 只有名称字段的表单（租房渠道 / 订阅分类）。
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
  });

  final String title;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        AppActionRow(
          first: AppSecondaryButton(
            label: '取消',
            compact: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          second: AppPrimaryButton(
            label: '保存',
            compact: true,
            onPressed: () {
              final String name = _name.text.trim();
              if (name.isEmpty) {
                setState(() => _error = '请填写${widget.label}');
                return;
              }
              Navigator.of(context)
                  .pop(<String, dynamic>{'name': name});
            },
          ),
        ),
      ],
    );
  }
}
