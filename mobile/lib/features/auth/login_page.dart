import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';

/// 登录页：`POST /api/v1/auth/login`，成功后令牌落盘并返回来源页。
///
/// 页面同时显示当前请求前缀，方便真机排查「是否连到了局域网 IP」。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _account = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppScope scope = AppScope.of(context);
    final String account = _account.text.trim();
    final String password = _password.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入账号与密码');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await scope.auth.login(account: account, password: password);
      if (!mounted) {
        return;
      }
      final String name = scope.auth.user?.displayName ?? account;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已登录：$name')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        // 独立登录页登录成功后同样落第一个 Tab，与冷启动口径保持一致。
        context.go('/health');
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final AppScope scope = AppScope.of(context);

    return DetailPageScaffold(
      title: '登录',
      child: ListView(
        children: <Widget>[
          Text('LifeOS 账号', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '登录后五个 Tab 会加载真实总览数据。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _account,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '账号',
              hintText: '如 admin',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitting ? null : _submit(),
            decoration: const InputDecoration(
              labelText: '密码',
              hintText: '至少 6 位',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
          const SizedBox(height: 12),
          Text(
            '连续失败 5 次会锁定 15 分钟；若提示连接失败，请先到「设置 → 服务器地址」改为局域网 IP。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<String>(
            valueListenable: scope.apiClient.baseUrlListenable,
            builder: (BuildContext context, String baseUrl, _) {
              return Text(
                '当前请求前缀：$baseUrl',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              );
            },
          ),
        ],
      ),
    );
  }
}

