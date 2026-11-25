import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

/// 关于页：应用名、版本号（来自安装包信息，即构建时的 `pubspec.yaml`）、
/// 包名、当前后端地址与「检查更新」入口。
///
/// 「检查更新」只做局域网自用版：启动时静默检查一次，发现新版才在这里和
/// 设置页显示标记；不弹窗、不强制。
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
    final AppTokens tokens = AppTokens.of(context);
    final AppScope scope = AppScope.of(context);
    final PackageInfo? info = _info;
    // 版本号只展示语义版本；构建号是开发侧信息，不适合直接给用户看。
    final String version = info == null ? '读取中…' : info.version;

    return DetailPageScaffold(
      title: '关于',
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          // 首屏先给「这是什么、什么版本」，再展开明细。
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: <Widget>[
                Text(
                  AppConfig.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.largeTitle.copyWith(
                    fontSize: 28,
                    color: tokens.text,
                  ),
                ),
                Text(
                  '版本 $version',
                  style: AppType.rowMeta.copyWith(color: tokens.text2),
                ),
              ],
            ),
          ),
          const SectionHeader(title: '应用信息'),
          GroupCard(
            children: <Widget>[
              RecordRow(title: '应用名', value: AppConfig.appName),
              RecordRow(title: '版本号', value: version),
              _InfoBlock(label: '包名', value: info?.packageName ?? '读取中…'),
            ],
          ),
          const SectionHeader(title: '后端地址'),
          GroupCard(
            children: <Widget>[
              ValueListenableBuilder<String>(
                valueListenable: scope.apiClient.baseUrlListenable,
                builder: (BuildContext context, String baseUrl, _) {
                  return _InfoBlock(label: '当前地址', value: baseUrl);
                },
              ),
            ],
          ),
          ListenableBuilder(
            listenable: scope.update,
            builder: (BuildContext context, _) {
              final bool hasUpdate = scope.update.hasUpdate;
              final String latest = scope.update.latest?.versionName ?? '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SectionHeader(title: '版本更新'),
                  GroupCard(
                    children: <Widget>[
                      RecordRow(
                        title: '当前版本',
                        value: scope.update.currentVersionCode > 0
                            ? '$version（${scope.update.currentVersionCode}）'
                            : version,
                      ),
                      V2EntryRow(
                        icon: Icons.system_update_alt,
                        title: '检查更新',
                        trailing: hasUpdate
                            ? V2Badge('有新版本 $latest', tone: V2BadgeTone.info)
                            : null,
                        onTap: () => context.push('/settings/update'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SectionHeader(title: '条款与许可'),
          GroupCard(
            children: <Widget>[
              V2EntryRow(
                icon: Icons.privacy_tip_outlined,
                title: '隐私政策',
                onTap: () => _showPrivacyPolicy(context),
              ),
              V2EntryRow(
                icon: Icons.code_outlined,
                title: '开源许可',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConfig.appName,
                  applicationVersion: version,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '安装包由局域网服务器 /api/v1/downloads 分发；'
              '下载完成后会校验 SHA-256，安装由系统安装器完成。',
              style: AppType.rowMeta.copyWith(color: tokens.text3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 隐私政策：说明数据去向与本地存储范围。
///
/// 没有后端页面可跳，内容按 App 实际行为写（自建服务端、令牌安全存储、
/// 本地只存界面偏好、无第三方统计 SDK），避免放一个空链接。
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

/// 标签在上、值独占一行的展示块：用于包名、后端地址这类长字符串。
class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: <Widget>[
          Text(
            label,
            style: AppType.rowMeta.copyWith(color: tokens.text2),
          ),
          SelectableText(
            value,
            style: AppType.rowTitle.copyWith(color: tokens.text),
          ),
        ],
      ),
    );
  }
}
