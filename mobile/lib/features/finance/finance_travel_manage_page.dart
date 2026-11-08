import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 旅行字典维护：行程账本（名称 / 起止日期 / 备注）与支付方式（名称）。
///
/// 对应后端标准 CRUD：
/// - `/finance/travel/ledgers`
/// - `/finance/travel/payment-channels`
/// 删除账本不会删除其下明细，明细会显示为「未归属行程」。
class FinanceTravelManagePage extends StatefulWidget {
  const FinanceTravelManagePage({super.key});

  @override
  State<FinanceTravelManagePage> createState() =>
      _FinanceTravelManagePageState();
}

class _FinanceTravelManagePageState extends State<FinanceTravelManagePage> {
  List<_Ledger> _ledgers = const <_Ledger>[];
  List<_Channel> _channels = const <_Channel>[];
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

  /// 并行拉取两个字典；任一失败都提示但不阻塞另一块。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    try {
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/finance/travel/ledgers',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/finance/travel/payment-channels',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data),
        ],
      );
      if (!mounted) {
        return;
      }
      final Map<String, dynamic>? ledgerJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? channelJson =
          responses[1] as Map<String, dynamic>?;
      setState(() {
        _ledgers = ((ledgerJson?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(_Ledger.fromJson)
            .toList();
        _channels = ((channelJson?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(_Channel.fromJson)
            .toList();
        _loading = false;
        _error = null;
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

  /// 保存账本：id 为空走 POST，否则 PUT。
  Future<void> _saveLedger(_LedgerDraft draft, _Ledger? existing) async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': draft.name,
      'start_date': draft.startDate,
      'end_date': draft.endDate,
      'note': draft.note,
    };
    try {
      if (existing == null) {
        await scope.apiClient
            .post<Map<String, dynamic>>('/finance/travel/ledgers', data: payload);
      } else {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/travel/ledgers/${existing.id}',
          data: payload,
        );
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(existing == null ? '已新增行程' : '已更新行程')),
      );
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('保存失败：${error.message}')));
      }
    }
  }

  /// 保存支付方式：id 为空走 POST，否则 PUT。
  Future<void> _saveChannel(_Channel? existing, String name) async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      if (existing == null) {
        await scope.apiClient.post<Map<String, dynamic>>(
          '/finance/travel/payment-channels',
          data: <String, dynamic>{'name': name},
        );
      } else {
        await scope.apiClient.put<Map<String, dynamic>>(
          '/finance/travel/payment-channels/${existing.id}',
          data: <String, dynamic>{'name': name},
        );
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(existing == null ? '已新增支付方式' : '已更新支付方式')),
      );
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('保存失败：${error.message}')));
      }
    }
  }

  /// 删除账本：二次确认，说明明细会变成「未归属行程」。
  Future<void> _deleteLedger(_Ledger ledger) async {
    final bool? confirmed = await _confirm(
      title: '删除行程「${ledger.name}」？',
      content: '该行程下的明细不会被删除，但会显示为「未归属行程」，且无法恢复。',
    );
    if (confirmed != true) {
      return;
    }
    await _delete('/finance/travel/ledgers/${ledger.id}', '已删除行程');
  }

  /// 删除支付方式：二次确认，历史明细中已保存的值不受影响。
  Future<void> _deleteChannel(_Channel channel) async {
    final bool? confirmed = await _confirm(
      title: '删除支付方式「${channel.name}」？',
      content: '已保存的明细仍保留原支付方式文本，仅后续新增时不再出现该选项。',
    );
    if (confirmed != true) {
      return;
    }
    await _delete('/finance/travel/payment-channels/${channel.id}', '已删除支付方式');
  }

  /// 删除请求与错误提示。
  Future<void> _delete(String path, String successText) async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await scope.apiClient.delete<dynamic>(path);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(successText)));
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('删除失败：${error.message}')));
      }
    }
  }

  /// 通用二次确认对话框。
  Future<bool?> _confirm({required String title, required String content}) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
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
  }

  /// 打开账本编辑表单。
  Future<void> _openLedgerForm([_Ledger? ledger]) async {
    final _LedgerDraft? draft = await showModalBottomSheet<_LedgerDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _LedgerFormSheet(initial: ledger),
    );
    if (draft == null || !mounted) {
      return;
    }
    await _saveLedger(draft, ledger);
  }

  /// 打开支付方式编辑表单（只含名称）。
  Future<void> _openChannelForm([_Channel? channel]) async {
    final String? name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _NameFormSheet(
        title: channel == null ? '新增支付方式' : '编辑支付方式',
        initial: channel?.name ?? '',
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    await _saveChannel(channel, name);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '行程与支付方式',
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
                  Text(
                    '加载失败：$_error',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  TextButton(onPressed: _refresh, child: const Text('重试')),
                ],
              )
            else ...<Widget>[
              SectionCard(
                title: '行程账本',
                trailing: TextButton.icon(
                  onPressed: () => _openLedgerForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
                child: _ledgers.isEmpty
                    ? Text(
                        '暂无行程，点右上角「新增」创建',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        children: <Widget>[
                          for (final _Ledger ledger in _ledgers)
                            _DictionaryRow(
                              title: ledger.name,
                              subtitle: ledger.rangeText,
                              onEdit: () => _openLedgerForm(ledger),
                              onDelete: () => _deleteLedger(ledger),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: '支付方式',
                trailing: TextButton.icon(
                  onPressed: () => _openChannelForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
                child: _channels.isEmpty
                    ? Text(
                        '暂无支付方式，点右上角「新增」创建',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        children: <Widget>[
                          for (final _Channel channel in _channels)
                            _DictionaryRow(
                              title: channel.name,
                              onEdit: () => _openChannelForm(channel),
                              onDelete: () => _deleteChannel(channel),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
    );
  }
}

/// 行程账本。
class _Ledger {
  const _Ledger({
    required this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.note,
  });

  factory _Ledger.fromJson(Map<dynamic, dynamic> json) {
    return _Ledger(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '未命名行程',
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      note: json['note'] as String?,
    );
  }

  final int id;
  final String name;
  final String? startDate;
  final String? endDate;
  final String? note;

  /// 起止日期展示：都空时返回空串，只有一端时按「起 / 止」展示。
  String get rangeText {
    if ((startDate ?? '').isEmpty && (endDate ?? '').isEmpty) {
      return '';
    }
    return '${startDate ?? '—'} ~ ${endDate ?? '—'}';
  }
}

/// 支付方式。
class _Channel {
  const _Channel({required this.id, required this.name});

  factory _Channel.fromJson(Map<dynamic, dynamic> json) {
    return _Channel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
    );
  }

  final int id;
  final String name;
}

/// 账本表单返回值。
class _LedgerDraft {
  const _LedgerDraft({
    required this.name,
    this.startDate,
    this.endDate,
    this.note,
  });

  final String name;
  final String? startDate;
  final String? endDate;
  final String? note;
}

/// 字典行：标题 + 副标题 + 编辑 / 删除菜单。
class _DictionaryRow extends StatelessWidget {
  const _DictionaryRow({
    required this.title,
    this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 8,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
                onEdit();
              } else {
                onDelete();
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
              PopupMenuItem<String>(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 账本编辑底部表单。
class _LedgerFormSheet extends StatefulWidget {
  const _LedgerFormSheet({this.initial});

  final _Ledger? initial;

  @override
  State<_LedgerFormSheet> createState() => _LedgerFormSheetState();
}

class _LedgerFormSheetState extends State<_LedgerFormSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _startDate;
  String? _endDate;

  @override
  void initState() {
    super.initState();
    final _Ledger? initial = widget.initial;
    if (initial != null) {
      _name.text = initial.name;
      _note.text = initial.note ?? '';
      _startDate = initial.startDate;
      _endDate = initial.endDate;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 选择起止日期，返回 `YYYY-MM-DD`。
  Future<void> _pickDate(bool start) async {
    final String? current = start ? _startDate : _endDate;
    final DateTime initial =
        DateTime.tryParse(current ?? '') ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    String two(int value) => value < 10 ? '0$value' : '$value';
    final String text = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    setState(() {
      if (start) {
        _startDate = text;
      } else {
        _endDate = text;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: <Widget>[
            Text(
              widget.initial == null ? '新增行程' : '编辑行程',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '行程名称'),
            ),
            Row(
              spacing: 12,
              children: <Widget>[
                Expanded(
                  child: _DateTile(
                    label: '开始日期',
                    value: _startDate,
                    onTap: () => _pickDate(true),
                  ),
                ),
                Expanded(
                  child: _DateTile(
                    label: '结束日期',
                    value: _endDate,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            AppPrimaryButton(
              label: '保存',
              onPressed: () {
                final String name = _name.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请填写行程名称')),
                  );
                  return;
                }
                Navigator.of(context).pop(
                  _LedgerDraft(
                    name: name,
                    startDate: _startDate,
                    endDate: _endDate,
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期选择瓦片。
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          value ?? '未选择',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: value == null ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }
}

/// 只含名称的底部表单（支付方式）。
class _NameFormSheet extends StatefulWidget {
  const _NameFormSheet({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameFormSheet> createState() => _NameFormSheetState();
}

class _NameFormSheetState extends State<_NameFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: <Widget>[
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            AppPrimaryButton(
              label: '保存',
              onPressed: () {
                final String name = _name.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请填写名称')),
                  );
                  return;
                }
                Navigator.of(context).pop(name);
              },
            ),
          ],
        ),
      ),
    );
  }
}
