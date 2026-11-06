import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/section_status.dart';

/// 账户设置：基本资料编辑（昵称 / 邮箱 / 手机 / 签名）+ 登录密码修改。
///
/// 接口（与网页端 `pages/settings/profile.tsx` 等一致）：
/// - `GET /user/profile` 与 `GET /user/settings`（并行）读取资料与密码状态；
/// - `PUT /user/profile` 保存资料；
/// - `PUT /user/settings` 修改密码（后端要求 `current_password` 校验）。
///
/// 写操作直接打接口、不进离线队列：资料与密码即时生效，失败只需提示重试。
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final GlobalKey<FormState> _profileForm = GlobalKey<FormState>();
  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _signature = TextEditingController();
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  LoadStatus _status = LoadStatus.loading;
  String? _message;
  String _account = '';
  bool _hasPassword = false;
  bool _savingProfile = false;
  bool _savingPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    _phone.dispose();
    _signature.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  /// 并行读取资料与账号设置；任一失败都进入可重试的失败态。
  Future<void> _load() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _status = LoadStatus.loading;
      _message = null;
    });
    try {
      final List<Object?> responses = await Future.wait<Object?>(<Future<Object?>>[
        scope.apiClient
            .get<Map<String, dynamic>>('/user/profile')
            .then((value) => value.data),
        scope.apiClient
            .get<Map<String, dynamic>>('/user/settings')
            .then((value) => value.data),
      ]);
      final Map<String, dynamic>? profile =
          responses[0] as Map<String, dynamic>?;
      final Map<String, dynamic>? settings =
          responses[1] as Map<String, dynamic>?;
      if (profile == null || settings == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '账户接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _nickname.text = (profile['nickname'] as String?) ?? '';
        _email.text = (profile['email'] as String?) ?? '';
        _phone.text = (profile['phone'] as String?) ?? '';
        _signature.text = (profile['signature'] as String?) ?? '';
        _account = (settings['account'] as String?) ?? '';
        _hasPassword = (settings['has_password'] as bool?) ?? false;
        _status = LoadStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _errorStatus(scope, error);
        _message = error.message;
      });
    }
  }

  /// 保存资料：昵称必填，邮箱做轻量格式校验，空字符串按清除处理。
  Future<void> _saveProfile() async {
    if (!(_profileForm.currentState?.validate() ?? false)) {
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _savingProfile = true);
    try {
      await scope.apiClient.put<Map<String, dynamic>>(
        '/user/profile',
        data: <String, dynamic>{
          'nickname': _nickname.text.trim(),
          'email': _blankToNull(_email.text),
          'phone': _blankToNull(_phone.text),
          'signature': _blankToNull(_signature.text),
        },
      );
      // 刷新 AuthService 中的用户对象：设置页账户卡立即显示新昵称。
      await scope.auth.refreshProfile();
      if (!mounted) {
        return;
      }
      _snack('资料已保存');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _snack('保存失败：${error.message}');
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  /// 修改密码：长度 ≥ 6、两次输入一致；已有密码时后端会校验当前密码。
  Future<void> _savePassword() async {
    final String next = _newPassword.text.trim();
    if (next.length < 6) {
      _snack('新密码长度不能少于 6 位');
      return;
    }
    if (next != _confirmPassword.text.trim()) {
      _snack('两次输入的新密码不一致');
      return;
    }
    if (_hasPassword && _currentPassword.text.trim().isEmpty) {
      _snack('请填写当前密码');
      return;
    }
    final AppScope scope = AppScope.of(context);
    setState(() => _savingPassword = true);
    try {
      await scope.apiClient.put<Map<String, dynamic>>(
        '/user/settings',
        data: <String, dynamic>{
          if (_hasPassword) 'current_password': _currentPassword.text.trim(),
          'new_password': next,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _hasPassword = true);
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      _snack('密码已修改');
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _snack('修改失败：${error.message}');
    } finally {
      if (mounted) {
        setState(() => _savingPassword = false);
      }
    }
  }

  String? _blankToNull(String raw) {
    final String value = raw.trim();
    return value.isEmpty ? null : value;
  }

  /// 列表页错误分流：未登录 / 已保留登录态的连接失败 / 普通失败。
  LoadStatus _errorStatus(AppScope scope, ApiException error) {
    if (error.isUnauthorized) {
      return LoadStatus.unauthenticated;
    }
    final bool offline = scope.auth.hasLocalSession &&
        (error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout);
    return offline ? LoadStatus.connectionFailed : LoadStatus.failed;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool ready = _status == LoadStatus.ready;

    return DetailPageScaffold(
      title: '账户设置',
      child: ListView(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: <Widget>[
              ListStatusView(
                status: _status,
                message: _message,
                onRetry: _load,
              ),
              if (ready) ...<Widget>[
                SectionCard(
                  title: '基本资料',
                  child: Form(
                    key: _profileForm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: <Widget>[
                        TextFormField(
                          controller: _nickname,
                          maxLength: 20,
                          decoration: const InputDecoration(
                            labelText: '昵称',
                            counterText: '',
                          ),
                          validator: (String? value) {
                            if ((value ?? '').trim().isEmpty) {
                              return '昵称不能为空';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: '邮箱',
                            hintText: '可选',
                          ),
                          validator: (String? value) {
                            final String text = (value ?? '').trim();
                            if (text.isEmpty) {
                              return null;
                            }
                            final bool valid = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(text);
                            return valid ? null : '邮箱格式不正确';
                          },
                        ),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: '手机号',
                            hintText: '可选',
                          ),
                        ),
                        TextFormField(
                          controller: _signature,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: '个性签名',
                            hintText: '可选，展示在个人资料中',
                            counterText: '',
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _savingProfile ? null : _saveProfile,
                            child: _savingProfile
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('保存资料'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SectionCard(
                  title: '登录密码',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: <Widget>[
                      if (_account.isNotEmpty)
                        Text(
                          '账号：$_account',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_hasPassword)
                        TextFormField(
                          controller: _currentPassword,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '当前密码',
                          ),
                        )
                      else
                        Text(
                          '当前账号尚未设置密码；填写新密码即可设置。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      TextFormField(
                        controller: _newPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '新密码',
                          hintText: '至少 6 位',
                        ),
                      ),
                      TextFormField(
                        controller: _confirmPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '确认新密码',
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: FilledButton.tonal(
                          onPressed: _savingPassword ? null : _savePassword,
                          child: _savingPassword
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('修改密码'),
                        ),
                      ),
                      Text(
                        '密码修改成功后立即生效，其他设备上的登录状态不受影响。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
