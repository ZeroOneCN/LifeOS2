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
