import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../theme/app_tokens.dart';

/// 服务器地址设置页：编辑 + 校验 + 持久化 + 立即更新 ApiClient。
class ServerConfigPage extends StatefulWidget {
  const ServerConfigPage({super.key});

  @override
  State<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends State<ServerConfigPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;
  late TextEditingController _updateController;

  /// 当前 API 地址派生的默认更新服务器（只用于占位提示，不写回存储）。
  String _derivedUpdateBase = '';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final AppScope scope = AppScope.of(context);
      _controller = TextEditingController(text: scope.preferences.baseUrl);
      _updateController = TextEditingController(
        text: scope.preferences.updateBaseUrl ?? '',
      );
      _derivedUpdateBase = scope.apiClient.origin;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _updateController.dispose();
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

  /// 更新服务器地址校验：允许留空（跟随 API 地址），填了就只能是根地址。
  ///
  /// 不接受 `/api/v1` 前缀，避免与客户端拼接路径重复；带路径一律判为格式错。
  String? _validateUpdate(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return '格式应为 http(s)://host:port';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return '只填到端口即可，不要带 /api/v1 等路径';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    final String normalized = _controller.text.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    await scope.preferences.setBaseUrl(normalized);
    scope.apiClient.updateBaseUrl(normalized);
    await scope.preferences.setUpdateBaseUrl(_updateController.text);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('服务器地址已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return DetailPageScaffold(
      title: '服务器地址',
      bottomBar: AppPrimaryButton(label: '保存', onPressed: _save),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            SectionCard(
              title: '接口地址',
              child: TextFormField(
                controller: _controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'http://192.168.1.10:9015/api/v1',
                  helperText: '需包含 /api/v1；真机不能用 127.0.0.1',
                  helperMaxLines: 2,
                ),
                validator: _validate,
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '更新服务器',
              child: TextFormField(
                controller: _updateController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: _derivedUpdateBase,
                  helperText: '留空 = 跟随上面的服务器地址；只填 http(s)://host:port',
                  helperMaxLines: 2,
                ),
                validator: _validateUpdate,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '保存后立即生效并持久化；鉴权、401 自动刷新与令牌轮换'
                '由 ApiClient 统一处理。检查更新使用更新服务器地址下载 APK，'
                '局域网 IP 变化后在这里单独改即可。',
                style: AppType.rowMeta.copyWith(color: tokens.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
