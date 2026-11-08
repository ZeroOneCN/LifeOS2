import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';

/// 购物记录的平台 / 分类 / 账本维护面板 + xlsx 导入。
///
/// 与网页端对齐的能力边界：
/// - 平台：新增、删除（网页端没有重命名入口）；
/// - 分类：新增、重命名、删除；编辑时原样回传关键词 / 排除词 / 优先级 / 兜底标记，
///   避免后端全量覆盖把分类的自动匹配规则清空；
/// - 账本：新增、重命名、删除（标准 CRUD）；删除只解除记录归属，不删记录；
/// - 导入：选 .xlsx 后上传，可选归属账本；文件内有「账本」列时以列值为准。
Future<bool?> showShoppingManageSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ShoppingManageSheet(),
  );
}

class _ShoppingManageSheet extends StatefulWidget {
  const _ShoppingManageSheet();

  @override
  State<_ShoppingManageSheet> createState() => _ShoppingManageSheetState();
}

class _ShoppingManageSheetState extends State<_ShoppingManageSheet> {
  List<NamedOption> _platforms = <NamedOption>[];
  List<NamedOption> _ledgers = <NamedOption>[];
  List<_CategoryRow> _categories = <_CategoryRow>[];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/finance/shopping/ledgers',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data),
        ],
      );
      if (!mounted) {
        return;
      }
      final Map<String, dynamic>? platformJson =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? ledgerJson =
          responses[2] as Map<String, dynamic>?;
      setState(() {
        _platforms = ((platformJson?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) =>
                NamedOption.fromJson(item.cast<String, dynamic>()))
            .toList();
        _ledgers = ((ledgerJson?['items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) =>
                NamedOption.fromJson(item.cast<String, dynamic>()))
            .toList();
        _categories = (responses[1] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map item) =>
                _CategoryRow.fromJson(item.cast<String, dynamic>()))
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

  Future<void> _addPlatform() async {
    final String? name = await _askName(title: '新增平台', hint: '平台名称，例如京东');
    if (name == null) {
      return;
    }
    await _run(() async {
      await AppScope.of(context).apiClient.post<Map<String, dynamic>>(
        '/finance/shopping/platforms',
        data: <String, dynamic>{'name': name},
      );
      return '已新增平台「$name」';
    });
  }

  Future<void> _deletePlatform(NamedOption platform) async {
    final bool? confirmed = await _confirm(
      title: '删除平台「${platform.name}」？',
      content: '删除后该平台下的历史记录会保留，但不再归属该平台；记录本身与金额统计不受影响。',
    );
    if (confirmed != true) {
      return;
    }
    await _run(() async {
      await AppScope.of(context)
          .apiClient
          .delete<dynamic>('/finance/shopping/platforms/${platform.id}');
      return '已删除平台「${platform.name}」';
    });
  }

  Future<void> _addCategory() async {
    final String? name =
        await _askName(title: '新增分类', hint: '分类名称，例如日用品');
    if (name == null) {
      return;
    }
    await _run(() async {
      await AppScope.of(context).apiClient.post<Map<String, dynamic>>(
        '/finance/shopping/categories',
        data: <String, dynamic>{'name': name},
      );
      return '已新增分类「$name」';
    });
  }

  Future<void> _renameCategory(_CategoryRow category) async {
    final String? name = await _askName(
      title: '重命名分类',
      hint: '分类名称',
      initial: category.name,
    );
    if (name == null || name == category.name) {
      return;
    }
    await _run(() async {
      // 全量字段回传，避免默认值覆盖关键词与优先级。
      await AppScope.of(context).apiClient.put<Map<String, dynamic>>(
        '/finance/shopping/categories/${category.id}',
        data: <String, dynamic>{
          'name': name,
          'keywords': category.keywords,
          'exclude': category.exclude,
          'priority': category.priority,
          'is_fallback': category.isFallback,
        },
      );
      return '已重命名为「$name」';
    });
  }

  Future<void> _deleteCategory(_CategoryRow category) async {
    final bool? confirmed = await _confirm(
      title: '删除分类「${category.name}」？',
      content: '删除后该分类下的历史记录会变为「未分类」，关键词匹配规则一并移除，且无法恢复。',
    );
    if (confirmed != true) {
      return;
    }
    await _run(() async {
      await AppScope.of(context)
          .apiClient
          .delete<dynamic>('/finance/shopping/categories/${category.id}');
      return '已删除分类「${category.name}」';
    });
  }

  Future<void> _addLedger() async {
    final String? name =
        await _askName(title: '新增账本', hint: '账本名称，例如日常开销');
    if (name == null) {
      return;
    }
    await _run(() async {
      await AppScope.of(context).apiClient.post<Map<String, dynamic>>(
        '/finance/shopping/ledgers',
        data: <String, dynamic>{'name': name},
      );
      return '已新增账本「$name」';
    });
  }

  Future<void> _renameLedger(NamedOption ledger) async {
    final String? name = await _askName(
      title: '重命名账本',
      hint: '账本名称',
      initial: ledger.name,
    );
    if (name == null || name == ledger.name) {
      return;
    }
    await _run(() async {
      await AppScope.of(context).apiClient.put<Map<String, dynamic>>(
        '/finance/shopping/ledgers/${ledger.id}',
        data: <String, dynamic>{'name': name},
      );
      return '已重命名为「$name」';
    });
  }

  Future<void> _deleteLedger(NamedOption ledger) async {
    final bool? confirmed = await _confirm(
      title: '删除账本「${ledger.name}」？',
      content: '账本删除后，其中的购物记录会保留，但归属账本被清空；'
          '记录本身与金额统计不受影响，且无法恢复账本。',
    );
    if (confirmed != true) {
      return;
    }
    await _run(() async {
      await AppScope.of(context)
          .apiClient
          .delete<dynamic>('/finance/shopping/ledgers/${ledger.id}');
      return '已删除账本「${ledger.name}」';
    });
  }

  /// 选择 xlsx 并上传；文件内没有账本列时，落到用户选中的账本。
  ///
  /// 上传后以接口返回的 `imported / skipped` 为准展示结果，
  /// 不在客户端自行推算条数（去重与自动分类都在后端完成）。
  Future<void> _importXlsx() async {
    final int? choice = await _pickLedgerForImport();
    if (!mounted) {
      return;
    }
    // null / -1 = 取消；-2 = 不指定账本；其余为账本 id。
    if (choice == null || choice == -1) {
      return;
    }
    final int? ledgerId = choice == -2 ? null : choice;
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['xlsx', 'xlsm'],
    );
    final String? path = file?.path;
    if (path == null || path.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppScope scope = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final FormData form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(path, filename: file?.name),
      });
      final Map<String, dynamic>? json = (await scope.apiClient
              .postMultipart<Map<String, dynamic>>(
            '/finance/shopping/import',
            data: form,
            queryParameters: ledgerId == null
                ? null
                : <String, dynamic>{'ledger_id': ledgerId},
          ))
          .data;
      if (!mounted) {
        return;
      }
      final int imported = (json?['imported'] as num?)?.toInt() ?? 0;
      final int skipped = (json?['skipped'] as num?)?.toInt() ?? 0;
      setState(() {
        _busy = false;
        _changed = true;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('导入完成：新增 $imported 条，跳过重复或无效 $skipped 条'),
        ),
      );
      await _load();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '导入失败：${error.message}';
      });
    }
  }

  /// 导入前选归属账本：返回 -1/null = 取消；-2 = 不指定；其余为账本 id。
  ///
  /// 没有账本时直接返回 -2（不指定），让后端按「无账本」落库。
  Future<int?> _pickLedgerForImport() async {
    if (_ledgers.isEmpty) {
      return -2;
    }
    return showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          title: const Text('导入到哪个账本？'),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(-1),
              child: const Text('取消导入'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(-2),
              child: const Text('不指定账本（文件内「账本」列优先）'),
            ),
            for (final NamedOption ledger in _ledgers)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(ledger.id),
                child: Text(ledger.name),
              ),
          ],
        );
      },
    );
  }

  /// 统一执行写请求：成功后重载列表并提示，失败只更新错误条。
  Future<void> _run(Future<String> Function() action) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String message = await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _changed = true;
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
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
  }

  Future<String?> _askName({
    required String title,
    required String hint,
    String? initial,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: initial);
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (String text) =>
                Navigator.of(dialogContext).pop(text.trim()),
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              second: AppPrimaryButton(
                label: '确定',
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('平台 / 分类维护', style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(_changed),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        children: <Widget>[
                          _SectionHeader(
                            title: '平台',
                            action: AppPrimaryAction(
                              label: '新增平台',
                              onPressed: _busy ? () {} : _addPlatform,
                            ),
                          ),
                          if (_platforms.isEmpty)
                            const _EmptyLine(text: '暂无平台，点右上新增')
                          else
                            for (final NamedOption item in _platforms)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(item.name),
                                trailing: IconButton(
                                  tooltip: '删除平台',
                                  onPressed:
                                      _busy ? null : () => _deletePlatform(item),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                          const SizedBox(height: 12),
                          _SectionHeader(
                            title: '分类',
                            action: AppPrimaryAction(
                              label: '新增分类',
                              onPressed: _busy ? () {} : _addCategory,
                            ),
                          ),
                          if (_categories.isEmpty)
                            const _EmptyLine(text: '暂无分类，点右上新增')
                          else
                            for (final _CategoryRow item in _categories)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(item.name),
                                subtitle: item.keywords.isEmpty
                                    ? const Text('无自动匹配关键词')
                                    : Text(
                                        '关键词：${item.keywords.join('、')}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: '重命名',
                                      onPressed: _busy
                                          ? null
                                          : () => _renameCategory(item),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: '删除分类',
                                      onPressed: _busy
                                          ? null
                                          : () => _deleteCategory(item),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                          const SizedBox(height: 12),
                          _SectionHeader(
                            title: '账本',
                            action: AppPrimaryAction(
                              label: '新增账本',
                              onPressed: _busy ? () {} : _addLedger,
                            ),
                          ),
                          if (_ledgers.isEmpty)
                            const _EmptyLine(text: '暂无账本，点右上新增')
                          else
                            for (final NamedOption item in _ledgers)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(item.name),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: '重命名账本',
                                      onPressed:
                                          _busy ? null : () => _renameLedger(item),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: '删除账本',
                                      onPressed:
                                          _busy ? null : () => _deleteLedger(item),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 8,
                              children: <Widget>[
                                Text(
                                  '从 Excel 导入',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  '表头需含：日期、商品名称、总价；可选平台 / 规格 / 单价 / 订单号 / 账本。'
                                  '订单号+日期+商品+总价 相同视为重复，自动跳过。',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                AppPrimaryButton(
                                  label: '选择 .xlsx 导入',
                                  icon: Icons.upload_file,
                                  onPressed: _busy ? null : _importXlsx,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        action,
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// 分类维护项：携带重命名时需要原样回传的全部字段。
class _CategoryRow {
  const _CategoryRow({
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

  factory _CategoryRow.fromJson(Map<String, dynamic> json) {
    return _CategoryRow(
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
