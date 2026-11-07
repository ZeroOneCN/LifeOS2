import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';

/// 关于页：应用名、版本号（来自安装包信息，即构建时的 `pubspec.yaml`）、
/// 包名与当前后端地址。
///
/// 后端没有版本 / 更新检查接口，因此不提供「检查更新」按钮，
/// 避免放了按钮却永远提示「已是最新」的假功能。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((PackageInfo info) {
      if (mounted) {
        setState(() => _info = info);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppScope scope = AppScope.of(context);
    final PackageInfo? info = _info;
    // 版本号只展示语义版本；构建号是开发侧信息，不适合直接给用户看。
    final String version = info == null ? '读取中…' : info.version;

    return DetailPageScaffold(
      title: '关于',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              SectionCard(
                title: '应用信息',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _InfoRow(label: '应用名', value: AppConfig.appName),
                    const Divider(height: 16),
                    _InfoRow(
                      label: '版本号',
                      value: version,
                    ),
                    const Divider(height: 16),
                    // 包名较长，独占一行避免在 375/1.3x 下从中间折断。
                    _InfoBlock(
                      label: '包名',
                      value: info?.packageName ?? '读取中…',
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '后端地址',
                child: ValueListenableBuilder<String>(
                  valueListenable: scope.apiClient.baseUrlListenable,
                  builder: (BuildContext context, String baseUrl, _) {
                    return _InfoBlock(label: '当前地址', value: baseUrl);
                  },
                ),
              ),
              SectionCard(
                title: '条款与许可',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _LinkRow(
                      icon: Icons.privacy_tip_outlined,
                      label: '隐私政策',
                      onTap: () => _showPrivacyPolicy(context),
                    ),
                    const Divider(height: 16),
                    _LinkRow(
                      icon: Icons.code_outlined,
                      label: '开源许可',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: AppConfig.appName,
                        applicationVersion: version,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '暂不提供「检查更新」：后端尚未提供版本或更新检查接口，'
                '安装包由局域网侧分发。',
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
}

/// 隐私政策：说明数据去向与本地存储范围。
///
/// 没有后端页面可跳，内容按 App 实际行为写（自建服务端、令牌安全存储、
/// 离线队列本地暂存、无第三方统计 SDK），避免放一个空链接。
Future<void> _showPrivacyPolicy(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final ThemeData theme = Theme.of(dialogContext);
      return AlertDialog(
        title: const Text('隐私政策'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              '1. 数据存放\n'
              '全部业务数据保存在你自己的 LifeOS 服务端，App 只通过你配置的地址'
              '读写，不上传任何第三方服务器。\n\n'
              '2. 本地存储\n'
              '登录令牌保存在系统安全存储；离线待提交的记录暂存在本机，'
              '提交成功后即清除。\n\n'
              '3. 设备权限\n'
              '蓝牙权限仅用于同步体重秤读数；通知权限用于本地提醒。'
              '两项都可随时在系统设置里关闭，不影响其它功能。\n\n'
              '4. 统计与广告\n'
              'App 不包含第三方广告或行为统计 SDK。\n\n'
              '5. 删除数据\n'
              '可在「设置 → 登录设备」下线其它设备；业务数据请在服务端删除。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}

/// 可点击的设置行：左侧图标 + 文案 + 右侧箭头。
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          spacing: 10,
          children: <Widget>[
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
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

/// 标签在上、值独占一行的展示块：用于包名、后端地址这类长字符串。
class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SelectableText(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
