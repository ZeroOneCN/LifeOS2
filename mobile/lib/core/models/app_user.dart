/// 当前登录用户（与后端 `UserMe` 对齐，不含密码信息）。
class AppUser {
  const AppUser({
    required this.id,
    required this.account,
    required this.nickname,
    required this.isAdmin,
    this.username,
    this.avatar,
    this.email,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      account: json['account'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      isAdmin: json['is_admin'] as bool? ?? false,
      username: json['username'] as String?,
      avatar: json['avatar'] as String?,
      email: json['email'] as String?,
    );
  }

  final int id;
  final String account;
  final String nickname;
  final bool isAdmin;
  final String? username;
  final String? avatar;
  final String? email;

  /// 顶栏/账户卡显示名：昵称优先，其次账号。
  String get displayName => nickname.isNotEmpty ? nickname : account;
}
