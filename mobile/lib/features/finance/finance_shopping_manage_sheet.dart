import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models/finance_models.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

/// 购物记录的平台 / 分类 / 账本维护面板 + xlsx 导入。
///
/// 与网页端对齐的能力边界：
/// - 平台：新增、删除（网页端没有重命名入口）；
/// - 分类：新增、重命名、删除；编辑时原样回传关键词 / 排除词 / 优先级 / 兜底标记，
///   避免后端全量覆盖把分类的自动匹配规则清空；
/// - 账本：新增、重命名、删除（标准 CRUD）；删除只解除记录归属，不删记录；
/// - 导入：选 .xlsx 后上传，可选归属账本；文件内有「账本」列时以列值为准。
///
/// 面板只能下滑或点击遮罩关闭，关闭时不带返回值；发生过写入通过 [onMutated]
/// 通知调用方刷新，避免「下滑关闭」与「返回结果」两条路径各写一套。
Future<void> showShoppingManageSheet(
  BuildContext context, {
  VoidCallback? onMutated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShoppingManageSheet(onMutated: onMutated),
  );
}

class _ShoppingManageSheet extends StatefulWidget {
  const _ShoppingManageSheet({this.onMutated});

  /// 面板内发生过写入时回调，供调用方刷新列表与汇总。
  final VoidCallback? onMutated;

  @override
  State<_ShoppingManageSheet> createState() => _ShoppingManageSheetState();
}

class _ShoppingManageSheetState extends State<_ShoppingManageSheet> {
  List<NamedOption> _platforms = <NamedOption>[];
  List<NamedOption> _ledgers = <NamedOption>[];
  List<_CategoryRow> _categories = <_CategoryRow>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// 标记面板内发生过写入：调用方据此刷新列表与汇总（下滑关闭同样生效）。
  void _notifyMutated() {
    widget.onMutated?.call();
  }

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
      });
      _notifyMutated();
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
      });
      _notifyMutated();
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

  /// 行尾「编辑 / 删除」菜单：图标统一 text3，删除项用危险色。
  Widget _actionMenu(
    AppTokens tokens, {
    VoidCallback? onEdit,
    required VoidCallback onDelete,
  }) {
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: 18, color: tokens.text3),
      onSelected: (String value) {
        if (value == 'edit') {
          onEdit?.call();
        } else {
          onDelete();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (onEdit != null)
          const PopupMenuItem<String>(
            value: 'edit',
            child: Text('编辑'),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: tokens.red)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
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
              // 弹层自带顶部拖拽手柄，可下滑关闭，不再额外放右上角关闭按钮。
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '平台 / 分类维护',
                  style: AppType.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: V2ErrorBanner(message: _error!),
                ),
              if (_busy)
                LinearProgressIndicator(minHeight: 2, color: tokens.accent),
              Flexible(
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(color: tokens.text2),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: <Widget>[
                          SectionHeader(
                            title: '平台 · 共 ${_platforms.length} 个',
                            actionLabel: '新增平台',
                            onAction: _busy ? null : _addPlatform,
                          ),
                          GroupCard(
                            children: <Widget>[
                              if (_platforms.isEmpty)
                                const EmptyState(
                                  icon: Icons.storefront_outlined,
                                  title: '暂无平台',
                                  description: '点「新增平台」录入第一个平台',
                                  compact: true,
                                )
                              else
                                for (final NamedOption item in _platforms)
                                  TaskRow(
                                    title: item.name,
                                    trailing: _actionMenu(
                                      tokens,
                                      onDelete: () => _deletePlatform(item),
                                    ),
                                  ),
                            ],
                          ),
                          SectionHeader(
                            title: '分类 · 共 ${_categories.length} 个',
                            actionLabel: '新增分类',
                            onAction: _busy ? null : _addCategory,
                          ),
                          GroupCard(
                            children: <Widget>[
                              if (_categories.isEmpty)
                                const EmptyState(
                                  icon: Icons.sell_outlined,
                                  title: '暂无分类',
                                  description: '点「新增分类」录入第一个分类',
                                  compact: true,
                                )
                              else
                                for (final _CategoryRow item in _categories)
                                  _CategoryTile(
                                    name: item.name,
                                    keywords: item.keywords,
                                    isFallback: item.isFallback,
                                    trailing: _actionMenu(
                                      tokens,
                                      onEdit: () => _renameCategory(item),
                                      onDelete: () => _deleteCategory(item),
                                    ),
                                  ),
                            ],
                          ),
                          SectionHeader(
                            title: '账本 · 共 ${_ledgers.length} 个',
                            actionLabel: '新增账本',
                            onAction: _busy ? null : _addLedger,
                          ),
                          GroupCard(
                            children: <Widget>[
                              if (_ledgers.isEmpty)
                                const EmptyState(
                                  icon: Icons.menu_book_outlined,
                                  title: '暂无账本',
                                  description: '点「新增账本」录入第一个账本',
                                  compact: true,
                                )
                              else
                                for (final NamedOption item in _ledgers)
                                  TaskRow(
                                    title: item.name,
                                    trailing: _actionMenu(
                                      tokens,
                                      onEdit: () => _renameLedger(item),
                                      onDelete: () => _deleteLedger(item),
                                    ),
                                  ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GroupCard(
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: 8,
                                  children: <Widget>[
                                    Text(
                                      '从 Excel 导入',
                                      style: AppType.section.copyWith(
                                        color: tokens.text2,
                                      ),
                                    ),
                                    Text(
                                      '表头需含：日期、商品名称、总价；可选平台 / 规格 / 单价 / 订单号 / 账本。'
                                      '订单号+日期+商品+总价 相同视为重复，自动跳过。',
                                      style: AppType.rowMeta.copyWith(
                                        color: tokens.text2,
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

/// 分类行：名称 + 可选兜底徽标在上，自动匹配关键词在下，右侧为操作菜单。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.keywords,
    required this.trailing,
    this.isFallback = false,
  });

  final String name;
  final List<String> keywords;
  final Widget trailing;
  final bool isFallback;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    spacing: 6,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.rowTitle.copyWith(color: tokens.text),
                        ),
                      ),
                      if (isFallback)
                        const V2Badge('兜底', tone: V2BadgeTone.gray),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    keywords.isEmpty
                        ? '无自动匹配关键词'
                        : '关键词：${keywords.join('、')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
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
