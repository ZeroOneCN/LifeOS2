import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 体检模板与组合维护。
///
/// 数据（与网页端口径一致，后端已有全套接口）：
/// - `GET /health/checkup/templates?page=1&page_size=100`：单指标模板；
/// - `POST /health/checkup/templates` / `PUT /.../{id}` / `DELETE /.../{id}`；
/// - `GET /health/checkup/panels`：组合模板（套餐）及其指标项；
/// - `POST /health/checkup/panels` / `PUT /health/checkup/panels/{id}` / `DELETE ...`。
///
/// 排序口径（全部由后端决定，表结构没有排序字段，移动端不提供手工拖动）：
/// - 单指标模板列表：`order_by=item_name`，`crud_router` 默认倒序；
/// - 组合列表：按 `panel_name` 升序；
/// - 组合内指标项：按 `item_name` 升序。
///
/// 删除影响：模板 / 组合只是「按模板录入」时的可选项来源；已保存的体检记录
/// 自带指标名、单位、参考范围（`template_id` 仅记录来源，无外键约束），
/// 删除模板不会改动任何历史记录。
class HealthCheckupTemplatePage extends StatefulWidget {
  const HealthCheckupTemplatePage({super.key});

  @override
  State<HealthCheckupTemplatePage> createState() =>
      _HealthCheckupTemplatePageState();
}

class _HealthCheckupTemplatePageState extends State<HealthCheckupTemplatePage> {
  final List<Map<String, dynamic>> _templates = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _panels = <Map<String, dynamic>>[];

  bool _initialized = false;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  /// 并行拉单指标模板与组合模板；任一失败整体失败，避免只显示一半。
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    if (!scope.auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '未登录，登录后可维护模板';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object?> responses = await Future.wait<Object?>(
        <Future<Object?>>[
          scope.apiClient
              .get<Map<String, dynamic>>(
                '/health/checkup/templates',
                queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
              )
              .then((value) => value.data),
          scope.apiClient
              .get<List<dynamic>>('/health/checkup/panels')
              .then((value) => value.data),
        ],
      );
      if (!mounted) {
        return;
      }
      final Map<String, dynamic>? templateJson =
          responses[0] as Map<String, dynamic>?;
      final List<dynamic> panelJson =
          (responses[1] as List<dynamic>?) ?? const <dynamic>[];
      setState(() {
        _templates
          ..clear()
          ..addAll(
            ((templateJson?['items'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<Map>()
                .map((Map item) => item.cast<String, dynamic>()),
          );
        _panels
          ..clear()
          ..addAll(
            panelJson.whereType<Map>().map(
              (Map item) => item.cast<String, dynamic>(),
            ),
          );
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '加载模板失败：${describeWriteFailure(error)}';
      });
    }
  }

  /// 打开单指标模板表单；保存成功后重拉。
  Future<void> _openTemplateForm([Map<String, dynamic>? initial]) async {
    final String path = initial == null
        ? '/health/checkup/templates/new'
        : '/health/checkup/templates/${initial['id']}/edit';
    final bool? changed = await context.push<bool>(path, extra: initial);
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 打开组合表单；保存成功后重拉。
  Future<void> _openPanelForm([Map<String, dynamic>? initial]) async {
    final String path = initial == null
        ? '/health/checkup/panels/new'
        : '/health/checkup/panels/${initial['id']}/edit';
    final bool? changed = await context.push<bool>(path, extra: initial);
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// 删除单指标模板：二次确认，说明只影响录入选项。
  Future<void> _deleteTemplate(Map<String, dynamic> template) async {
    final String name = template['item_name'] as String? ?? '该指标';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除该指标模板？'),
          content: Text(
            '将删除「$name」。\n'
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
    await _delete(
      path: '/health/checkup/templates/${template['id']}',
      success: '已删除模板「$name」',
    );
  }

  /// 删除组合模板：二次确认，说明只影响录入选项。
  Future<void> _deletePanel(Map<String, dynamic> panel) async {
    final String name = panel['panel_name'] as String? ?? '该组合';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除该组合模板？'),
          content: Text(
            '将删除「$name」及其全部指标项。\n'
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
    await _delete(
      path: '/health/checkup/panels/${panel['id']}',
      success: '已删除组合「$name」',
    );
  }

  /// 统一执行删除请求：成功提示并重拉，失败保留列表并提示。
  Future<void> _delete({required String path, required String success}) async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await scope.apiClient.delete<dynamic>(path);
      messenger.showSnackBar(SnackBar(content: Text(success)));
      await _refresh();
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('删除失败。${describeWriteFailure(error)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '模板与组合',
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
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
              SectionCard(
                title: '组合模板（套餐）',
                trailing: AppPrimaryAction(
                  label: '新建组合',
                  onPressed: _loading ? () {} : () => _openPanelForm(),
                ),
                child: _panels.isEmpty
                    ? const EmptyState(
                        icon: Icons.dashboard_customize_outlined,
                        title: '暂无组合模板',
                        description: '把常一起检查的指标组合成套餐，录入时一键带入',
                        compact: true,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final Map<String, dynamic> panel in _panels)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                panel['panel_name'] as String? ?? '未命名组合',
                              ),
                              subtitle: Text(
                                _panelSubtitle(panel),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _openPanelForm(panel),
                              trailing: IconButton(
                                tooltip: '删除组合',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deletePanel(panel),
                              ),
                            ),
                        ],
                      ),
              ),
              SectionCard(
                title: '单指标模板',
                trailing: AppPrimaryAction(
                  label: '新增指标',
                  onPressed: _loading ? () {} : () => _openTemplateForm(),
                ),
                child: _templates.isEmpty
                    ? const EmptyState(
                        icon: Icons.rule_outlined,
                        title: '暂无指标模板',
                        description: '新增模板后，录入时可一键带入指标名与参考范围',
                        compact: true,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final Map<String, dynamic> template
                              in _templates)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                template['item_name'] as String? ?? '未命名指标',
                              ),
                              subtitle: Text(
                                _templateSubtitle(template),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _openTemplateForm(template),
                              trailing: IconButton(
                                tooltip: '删除模板',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteTemplate(template),
                              ),
                            ),
                        ],
                      ),
              ),
              Text(
                '排序口径：单指标模板按名称倒序、组合与组合内指标按名称升序，'
                '均由后端排序，不支持手工拖动。\n'
                '删除影响：仅影响「按模板录入」的可选项，已保存的体检记录不受影响。',
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

  /// 组合副标题：指标项数 + 说明。
  String _panelSubtitle(Map<String, dynamic> panel) {
    final int count =
        ((panel['items'] as List<dynamic>?) ?? const <dynamic>[]).length;
    final String note = (panel['note'] as String? ?? '').trim();
    return note.isEmpty ? '$count 项指标' : '$count 项指标 · $note';
  }

  /// 模板副标题：类别 / 单位 / 参考区间，缺项不占位。
  String _templateSubtitle(Map<String, dynamic> template) {
    final List<String> parts = <String>[
      if ((template['category'] as String? ?? '').trim().isNotEmpty)
        (template['category'] as String).trim(),
      if ((template['unit'] as String? ?? '').trim().isNotEmpty)
        '单位 ${(template['unit'] as String).trim()}',
      '参考 ${_rangeText(template['ref_low'], template['ref_high'])}',
    ];
    return parts.join(' · ');
  }

  /// 上下限 → 展示文案：双有 `a~b`、单有 `≥a` / `≤b`、都没有「未设置」。
  String _rangeText(Object? low, Object? high) {
    final double? lo = (low as num?)?.toDouble();
    final double? hi = (high as num?)?.toDouble();
    if (lo != null && hi != null) {
      return '${_plain(lo)}~${_plain(hi)}';
    }
    if (lo != null) {
      return '≥ ${_plain(lo)}';
    }
    if (hi != null) {
      return '≤ ${_plain(hi)}';
    }
    return '未设置';
  }

  /// 去尾零。
  String _plain(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}
