import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/models/app_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/profile/profile_service.dart';
import '../../core/queue/outbox_controller.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/user_avatar.dart';
import 'avatar_preview_page.dart';

/// 设置根页：账户卡（含头像）+ 服务器地址 + 状态行 + 账户设置 + 外观 + 关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppScope scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        scope.auth,
        scope.overview,
        scope.outbox,
      ]),
      builder: (BuildContext context, _) {
        final AppUser? user = scope.auth.user;
        final bool offline = scope.auth.connectionFailed;
        return RootPageScaffold(
          title: '设置',
          children: <Widget>[
            _AccountCard(user: user, offline: offline),
            ValueListenableBuilder<String>(
              valueListenable: scope.apiClient.baseUrlListenable,
              builder: (BuildContext context, String baseUrl, _) {
                return EntryTile(
                  icon: Icons.dns_outlined,
                  title: '服务器地址',
                  subtitle: baseUrl,
                  onTap: () => context.push('/settings/server'),
                );
              },
            ),
            SectionCard(
              title: '状态',
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    label: '登录状态',
                    value: user != null
                        ? '已登录（${user.account}）'
                        : (offline ? '连接失败（已保留登录状态）' : '未登录'),
                  ),
                  const Divider(height: 16),
                  _InfoRow(
                    label: '总览数据',
                    value: scope.overview.health.hasData ||
                            scope.overview.finance.hasData
                        ? '已加载'
                        : '待加载',
                  ),
                  if (offline) ...<Widget>[
                    const Divider(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '无法连接服务器，点击右侧重试',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: scope.overview.retry,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SectionCard(
              title: '离线队列',
              child: Column(
                children: <Widget>[
                  _InfoRow(
                    label: '待同步',
                    value:
                        '${scope.outbox.pendingCount} / ${OutboxController.maxEntries} 条',
                  ),
                  const Divider(height: 16),
                  _InfoRow(
                    label: '上次同步',
                    value: _formatSyncTime(scope.outbox.lastSyncAt),
                  ),
                  if (!scope.outbox.isOnline) ...<Widget>[
                    const Divider(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '当前无网络，恢复后按入队顺序自动推送',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: null,
                          child: const Text('立即同步'),
                        ),
                      ],
                    ),
                  ] else if (scope.outbox.pendingCount > 0) ...<Widget>[
                    const Divider(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            scope.outbox.isSyncing
                                ? '正在同步…'
                                : (scope.outbox.needsManualRetry
                                    ? '自动重试已停止，请手动重试'
                                    : (scope.outbox.lastError ??
                                        '有积压，点击右侧立即推送')),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scope.outbox.lastError == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              scope.outbox.isSyncing ? null : scope.outbox.retryNow,
                          child: const Text('立即同步'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            EntryTile(
              icon: Icons.manage_accounts_outlined,
              title: '账户设置',
              subtitle: user == null ? '登录后可管理账号信息' : null,
              onTap: () => context.push(
                user == null ? '/login' : '/settings/account',
              ),
            ),
            EntryTile(
              icon: Icons.devices_outlined,
              title: '登录设备',
              subtitle: user == null
                  ? '登录后查看活跃会话'
                  : '查看活跃会话，下线其他设备',
              onTap: () => context.push(
                user == null ? '/login' : '/settings/devices',
              ),
            ),
            EntryTile(
              icon: Icons.backup_outlined,
              title: '数据备份',
              subtitle: user != null && !user.isAdmin
                  ? '仅管理员可导出，当前账号无权限'
                  : '导出整库备份并通过系统分享保存',
              onTap: () => context.push(
                user == null ? '/login' : '/settings/backup',
              ),
            ),
            SectionCard(
              title: '外观',
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: scope.preferences.themeMode,
                builder: (BuildContext context, ThemeMode mode, _) {
                  void select(ThemeMode? value) {
                    if (value != null) {
                      scope.preferences.setThemeMode(value);
                    }
                  }

                  return RadioGroup<ThemeMode>(
                    groupValue: mode,
                    onChanged: select,
                    child: Column(
                      children: <Widget>[
                        const RadioListTile<ThemeMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: ThemeMode.light,
                          title: Text('浅色'),
                        ),
                        const RadioListTile<ThemeMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: ThemeMode.dark,
                          title: Text('深色'),
                        ),
                        const RadioListTile<ThemeMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: ThemeMode.system,
                          title: Text('跟随系统'),
                        ),
                        Text(
                          '选择会立即生效，并在下次冷启动时保留。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            EntryTile(
              icon: Icons.info_outline,
              title: '关于',
              subtitle: '应用名、版本与后端地址',
              onTap: () => context.push('/settings/about'),
            ),
            Text(
              '点击头像查看大图（长按保存到相册）；更换或移除头像请在大图页底部操作。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 账户卡：头像 + 昵称/账号 + 退出（或登录/重试）。
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.offline});

  final AppUser? user;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppScope scope = AppScope.of(context);
    final AppUser? current = user;
    final String title = current != null
        ? current.displayName
        : (offline ? '连接失败' : '未登录');
    final String subtitle = current != null
        ? '账号 ${current.account}'
        : (offline ? '已保留登录状态，网络恢复后可重试' : '登录后可同步五个 Tab 的真实数据');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          current == null ? '/login' : '/settings/account',
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: <Widget>[
              GestureDetector(
                onTap: current == null
                    ? null
                    : () => _openAvatar(context, scope, current),
                child: Tooltip(
                  message: current == null
                      ? '登录后可设置头像'
                      : '点击查看头像大图',
                  child: UserAvatar(user: current, radius: 26),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: <Widget>[
                    Row(
                      spacing: 6,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (current?.isAdmin ?? false)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '管理员',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (current != null)
                AppDangerButton(
                  label: '退出',
                  icon: Icons.logout,
                  compact: true,
                  onPressed: () => _confirmLogout(context, scope),
                )
              else if (offline)
                TextButton(
                  onPressed: scope.overview.retry,
                  child: const Text('重试'),
                )
              else
                FilledButton.tonal(
                  onPressed: () => context.push('/login'),
                  child: const Text('登录'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点击头像：有头像进全屏预览（长按保存），无头像直接打开更换面板。
  ///
  /// 大图页底部「更换头像 / 移除头像」都返回 [AvatarPreviewAction.edit]，
  /// 关闭大图后在这里统一弹出原三条路径面板，不额外占用设置页版面。
  Future<void> _openAvatar(
    BuildContext context,
    AppScope scope,
    AppUser user,
  ) async {
    final String? url = scope.apiClient.resolveAvatar(user.avatar);
    if (url == null) {
      await showAvatarSheet(context, scope);
      return;
    }
    // 用根 Navigator 压栈：大图页必须盖住底部导航，才是真正的全屏预览。
    final AvatarPreviewAction? action = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<AvatarPreviewAction>(
      MaterialPageRoute<AvatarPreviewAction>(
        builder: (BuildContext _) => AvatarPreviewPage(url: url),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }
    await showAvatarSheet(context, scope);
  }

  /// 退出登录：先二次确认（说明离线队列的去留），再清本地令牌并回到「未登录」。
  ///
  /// 本地离线队列不会因登出而清空：未同步记录保留在本机，
  /// 下次登录后会按 FIFO 继续推送。
  Future<void> _confirmLogout(BuildContext context, AppScope scope) async {
    final int pending = scope.outbox.pendingCount;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('退出登录？'),
          content: Text(
            pending > 0
                ? '本机还有 $pending 条未同步记录。退出登录不会清空它们，'
                    '会保留在本机，下次登录后继续自动同步；但退出后需重新登录才能查看数据。'
                : '退出后需要重新输入账号密码才能登录，本机已同步的数据仍保留在服务器。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppDangerButton(
                label: '退出登录',
                icon: Icons.logout,
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await scope.auth.logout();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }
}

/// 头像操作面板：相册上传 / 填写地址 / 移除。
Future<void> showAvatarSheet(BuildContext context, AppScope scope) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _AvatarSheet(scope: scope),
  );
}

class _AvatarSheet extends StatefulWidget {
  const _AvatarSheet({required this.scope});

  final AppScope scope;

  @override
  State<_AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends State<_AvatarSheet> {
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;
  double _progress = 0;

  /// 相册选图 → 客户端校验 → 压缩后上传（带进度）。
  ///
  /// 压缩策略：交给 image_picker 的原生解码做「长边 1024 + JPEG 质量 85」缩放，
  /// 不引入额外图像库、也不在 Dart 主 isolate 上解码大图；
  /// 缩放后仍超过 2 MB 则直接提示重选（正常手机照片可落在 100–600 KB）。
  Future<void> _pickAndUpload() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) {
      return;
    }
    final File file = File(picked.path);
    final String? error = AvatarRules.validateFile(file);
    if (error != null) {
      _snack(error);
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await widget.scope.profile.uploadAvatar(
        file,
        onProgress: (int sent, int total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() => _progress = sent / total);
        },
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      _snack('头像已更新');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _snack('上传失败：${_hint(error)}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _snack('上传失败：$error');
    }
  }

  /// 填地址（或清空）→ 校验 → PUT `/user/avatar`。
  Future<void> _editUrl() async {
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _AvatarUrlDialog(),
    );
    if (value == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.scope.profile.setAvatarUrl(value);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      _snack('头像已更新');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _snack('设置失败：${_hint(error)}');
    }
  }

  /// 移除头像：先确认，再以 `avatar_url: null` 清空账号头像。
  Future<void> _remove() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('移除头像？'),
          content: const Text(
            '会从账号里删除当前头像，其他设备登录后也会同步消失；'
            '可以随时重新上传，但移除后无法恢复原图。',
          ),
          actions: <Widget>[
            AppActionRow(
              first: AppSecondaryButton(
                label: '取消',
                compact: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              second: AppDangerButton(
                label: '确认移除',
                icon: Icons.delete_outline,
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
    setState(() => _busy = true);
    try {
      await widget.scope.profile.setAvatarUrl(null);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      _snack('头像已移除');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _snack('移除失败：${_hint(error)}');
    }
  }

  /// 404 时提示后端版本，其余沿用服务端文案。
  String _hint(ApiException error) {
    if (error.kind == ApiErrorKind.notFound) {
      return '当前后端不支持头像接口（404），请确认后端已更新';
    }
    return error.message;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? avatar = widget.scope.auth.user?.avatar;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('更换头像', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_busy) ...<Widget>[
              LinearProgressIndicator(
                value: _progress > 0 && _progress < 1 ? _progress : null,
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0 && _progress < 1
                    ? '上传中 ${(_progress * 100).toStringAsFixed(0)}%'
                    : '正在处理…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            _Option(
              icon: Icons.photo_library_outlined,
              title: '从相册选择',
              subtitle: 'png / jpg / jpeg / webp，≤ 2 MB',
              onTap: _busy ? null : _pickAndUpload,
            ),
            _Option(
              icon: Icons.link_outlined,
              title: '填写图片地址',
              subtitle: '仅 http / https，≤ 255 字符',
              onTap: _busy ? null : _editUrl,
            ),
            if (avatar != null && avatar.isNotEmpty)
              _Option(
                icon: Icons.delete_outline,
                title: '移除头像',
                danger: true,
                onTap: _busy ? null : _remove,
              ),
            const SizedBox(height: 4),
            Text(
              '客户端会先按长边 1024、JPEG 质量 85 压缩再上传；'
              '不做裁剪（后端不处理裁剪）。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入外链头像地址的对话框。
///
/// 控制器由对话框自身持有：`showDialog` 返回的 Future 在退场动画结束前就已
/// 完成，若在调用方立刻 `dispose()` 控制器，退场期间 TextField 仍会重建并
/// 访问已销毁的控制器（`TextEditingController was used after being disposed`）。
class _AvatarUrlDialog extends StatefulWidget {
  const _AvatarUrlDialog();

  @override
  State<_AvatarUrlDialog> createState() => _AvatarUrlDialogState();
}

class _AvatarUrlDialogState extends State<_AvatarUrlDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    final String? error = AvatarRules.validateUrl(text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('填写图片地址'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        maxLength: 255,
        decoration: const InputDecoration(
          hintText: 'https://example.com/avatar.png',
          counterText: '',
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
            onPressed: _submit,
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        danger ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      leading: Icon(icon, color: danger ? theme.colorScheme.error : null),
      title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 上次同步时间的展示文本：本地时区 `MM-dd HH:mm`，从未同步显示占位。
String _formatSyncTime(DateTime? time) {
  if (time == null) {
    return '尚未同步';
  }
  final DateTime local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
