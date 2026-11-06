import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../theme/app_typography.dart';

/// 服务器地址设置页：编辑 + 校验 + 持久化 + 立即更新 ApiClient。
class ServerConfigPage extends StatefulWidget {
  const ServerConfigPage({super.key});

  @override
  State<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends State<ServerConfigPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _controller = TextEditingController(
        text: AppScope.of(context).preferences.baseUrl,
      );
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return '请输入服务器地址';
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return '格式应为 http(s)://host:port/api/v1';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final String normalized =
        _controller.text.trim().replaceFirst(RegExp(r'/+$'), '');
    await scope.preferences.setBaseUrl(normalized);
    scope.apiClient.updateBaseUrl(normalized);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('服务器地址已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DetailPageScaffold(
      title: '服务器地址',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          children: <Widget>[
            Text(
              '请求前缀',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.amountMedium,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.10:9015/api/v1',
                helperText: '需包含 /api/v1；真机不能用 127.0.0.1',
              ),
              validator: _validate,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
            const SizedBox(height: 16),
            Text(
              '保存后立即生效并持久化；鉴权、401 自动刷新与令牌轮换'
              '由 ApiClient 统一处理。',
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
