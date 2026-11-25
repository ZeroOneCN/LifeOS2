import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/data/overview_controller.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/root_page_scaffold.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/v2/v2_page_kit.dart';
import '../../shared/widgets/v2/v2_rows.dart';
import '../../theme/app_tokens.dart';

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

  LoadStatus _status = LoadStatus.loading;
  String? _message;
  String _account = '';
  bool _hasPassword = false;
  bool _savingProfile = false;

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
    final AppTokens tokens = AppTokens.of(context);

    return DetailPageScaffold(
      title: '账户设置',
      // 主操作固定在底栏，与账单 / 体重等表单页一致；密码修改拆到独立子页。
      bottomBar: AppPrimaryButton(
        label: '保存资料',
        loading: _savingProfile,
        onPressed: _saveProfile,
      ),
      child: ListPageBody(
        status: _status,
        message: _message,
        onRetry: _load,
        blocks: <Widget>[
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
                ],
              ),
            ),
          ),
          GroupCard(
            children: <Widget>[
              V2EntryRow(
                title: '修改登录密码',
                subtitle: _account.isEmpty
                    ? '在独立页面修改，成功后立即生效'
                    : '账号 $_account · ${_hasPassword ? '已设置密码' : '尚未设置密码'}',
                icon: Icons.lock_outline,
                onTap: () => context.push('/settings/account/password'),
              ),
            ],
          ),
          Text(
            '资料保存后立即生效；密码在独立页面修改。',
            style: AppType.rowMeta.copyWith(color: tokens.text3),
          ),
        ],
      ),
    );
  }
}
