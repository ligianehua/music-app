import 'package:flutter/foundation.dart';

import 'user.dart';

/// 账号服务。现在是本机实现，以后接服务器只需要换一个实现。
abstract class AuthService extends ChangeNotifier {
  /// 当前登录的用户；未登录为 null。
  AppUser? get currentUser;

  /// 注册并直接登录。
  Future<AppUser> register(String username, String password);

  Future<AppUser> login(String username, String password);

  Future<void> logout();

  /// 保存当前用户的听歌偏好。
  Future<AppUser> updatePreferences(UserPreferences preferences);
}

/// 注册、登录失败。[message] 直接展示给用户。
class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 用户名：2 到 20 个字符，任何语言的字母、数字、下划线、点。
final _usernamePattern = RegExp(r'^[\p{L}\p{N}_.]{2,20}$', unicode: true);

/// 校验用户名，合法时返回 null，否则返回提示语。
String? validateUsername(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Enter a username.';
  if (!_usernamePattern.hasMatch(name)) {
    return 'Use 2–20 letters, numbers, dots or underscores.';
  }
  return null;
}

/// 校验密码，合法时返回 null，否则返回提示语。
String? validatePassword(String password) {
  if (password.length < 6) return 'Use at least 6 characters.';
  if (password.length > 64) return 'Use 64 characters or fewer.';
  if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
      !RegExp(r'\d').hasMatch(password)) {
    return 'Include both letters and numbers.';
  }
  return null;
}
