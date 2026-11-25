import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../theme/app_tokens.dart';

/// 修改登录密码：独立子页，主操作固定在底栏，与其他表单页保持一致。
///
/// 接口：
/// - `GET /user/settings`：读取账号与是否已设置密码；
/// - `PUT /user/settings`：修改密码（已有密码时后端校验 `current_password`）。
class AccountPasswordPage extends StatefulWidget {
  const AccountPasswordPage({super.key});

  @override
  State<AccountPasswordPage> createState() => _AccountPasswordPageState();
}

class _AccountPasswordPageState extends State<AccountPasswordPage> {
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  LoadStatus _status = LoadStatus.loading;
  String? _message;
  String _account = '';
  bool _hasPassword = false;
  bool _saving = false;

  /// 密码可见性：默认隐藏，点眼睛图标临时显示，便于核对输入。
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

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
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  /// 读取账号与密码状态；失败进入可重试的失败态。
  Future<void> _load() async {
    final AppScope scope = AppScope.of(context);
    setState(() {
      _status = LoadStatus.loading;
      _message = null;
    });
    try {
      final Map<String, dynamic>? settings =
          (await scope.apiClient.get<Map<String, dynamic>>('/user/settings'))
              .data;
      if (settings == null) {
        throw const ApiException(
          kind: ApiErrorKind.badResponse,
          message: '账号设置接口返回数据为空',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
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

  /// 修改密码：长度 ≥ 6、两次输入一致；已有密码时必须填写当前密码。
  Future<void> _save() async {
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
    setState(() => _saving = true);
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
        setState(() => _saving = false);
      }
    }
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

  /// 密码输入框右侧的可见性开关。
  Widget _visibilityToggle({
    required bool visible,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
      ),
      tooltip: visible ? '隐藏密码' : '显示密码',
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return DetailPageScaffold(
      title: '修改密码',
      bottomBar: AppPrimaryButton(
        label: '保存',
        loading: _saving,
        onPressed: _save,
      ),
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _load,
        blocks: <Widget>[
          SectionCard(
            title: '登录密码',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: <Widget>[
                if (_account.isNotEmpty)
                  Text(
                    '账号：$_account',
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                if (_hasPassword)
                  TextFormField(
                    controller: _currentPassword,
                    obscureText: !_showCurrent,
                    decoration: InputDecoration(
                      labelText: '当前密码',
                      suffixIcon: _visibilityToggle(
                        visible: _showCurrent,
                        onPressed: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                    ),
                  )
                else
                  Text(
                    '当前账号尚未设置密码；填写新密码即可设置。',
                    style: AppType.rowMeta.copyWith(color: tokens.text2),
                  ),
                TextFormField(
                  controller: _newPassword,
                  obscureText: !_showNew,
                  decoration: InputDecoration(
                    labelText: '新密码',
                    hintText: '至少 6 位',
                    suffixIcon: _visibilityToggle(
                      visible: _showNew,
                      onPressed: () => setState(() => _showNew = !_showNew),
                    ),
                  ),
                ),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: !_showConfirm,
                  decoration: InputDecoration(
                    labelText: '确认新密码',
                    suffixIcon: _visibilityToggle(
                      visible: _showConfirm,
                      onPressed: () =>
                          setState(() => _showConfirm = !_showConfirm),
                    ),
                  ),
                ),
                Text(
                  '密码修改成功后立即生效，其他设备上的登录状态不受影响。',
                  style: AppType.rowMeta.copyWith(color: tokens.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
