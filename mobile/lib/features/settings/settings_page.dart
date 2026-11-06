import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/models/app_user.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 设置根页：账户卡 + 状态行（服务器地址 / 账户设置）+ 外观 + 关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppScope scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.auth, scope.overview]),
      builder: (BuildContext context, _) {
        final AppUser? user = scope.auth.user;
        return RootPageScaffold(
          title: '设置',
          children: <Widget>[
            _AccountCard(user: user),
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
                    value: user == null ? '未登录' : '已登录（${user.account}）',
                  ),
                  const Divider(height: 16),
                  _InfoRow(
                    label: '总览数据',
                    value: scope.overview.health.hasData ||
                            scope.overview.finance.hasData
                        ? '已加载'
                        : '待加载',
                  ),
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
            SectionCard(
              title: '外观',
              child: Column(
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.brightness_auto_outlined),
                    title: const Text('主题模式'),
                    subtitle: const Text('跟随系统深浅色'),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SectionCard(
              title: '关于',
              child: Column(
                children: <Widget>[
                  _InfoRow(label: '应用', value: 'LifeOS'),
                  _InfoRow(label: '版本', value: '1.0.0（P2）'),
                  _InfoRow(label: '包名', value: 'com.lifeos.mobile'),
                ],
              ),
            ),
            Text(
              'P2：服务器地址与登录已接入；五个 Tab 只接总览层数据，'
              '业务列表页仍为占位。',
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

/// 账户卡：已登录显示昵称/账号/管理员标记 + 退出；未登录引导去登录页。
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppScope scope = AppScope.of(context);
    final AppUser? current = user;
    final String title =
        current == null ? '未登录' : current.displayName;
    final String subtitle = current == null
        ? '登录后可同步五个 Tab 的真实数据'
        : '账号 ${current.account}';

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
              CircleAvatar(
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                child: current == null
                    ? Icon(
                        Icons.person_outline,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : Text(
                        String.fromCharCode(current.displayName.runes.first),
                        style: theme.textTheme.titleMedium,
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
              if (current == null)
                FilledButton.tonal(
                  onPressed: () => context.push('/login'),
                  child: const Text('登录'),
                )
              else
                TextButton(
                  onPressed: () => _logout(context, scope),
                  child: const Text('退出'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 退出登录：清本地令牌并让总览回到「未登录」状态，失败不阻塞。
  Future<void> _logout(BuildContext context, AppScope scope) async {
    await scope.auth.logout();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }
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

