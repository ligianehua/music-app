import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'password.dart';
import 'user.dart';

/// 本机账号：账号信息和密码哈希都存在这台手机上。
///
/// 这不是真正的会员系统：数据不出手机，换手机就没了，也挡不住拿到手机的人
/// 直接改存储。接服务器时换成远程实现即可，接口不变。
class LocalAuthService extends AuthService {
  LocalAuthService(this._prefs, {this.iterations = PasswordHash.defaultIterations}) {
    final id = _prefs.getString(_sessionKey);
    if (id != null) _current = _loadUsers()[_findNameById(id)]?.user;
  }

  static Future<LocalAuthService> open() async =>
      LocalAuthService(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final int iterations;
  AppUser? _current;

  static const _usersKey = 'auth_users';
  static const _sessionKey = 'auth_session';

  @override
  AppUser? get currentUser => _current;

  /// 用户名不区分大小写，存的时候统一成小写作为键。
  static String _key(String username) => username.trim().toLowerCase();

  @override
  Future<AppUser> register(String username, String password) async {
    final nameError = validateUsername(username);
    if (nameError != null) throw AuthException(nameError);
    final pwError = validatePassword(password);
    if (pwError != null) throw AuthException(pwError);

    final users = _loadUsers();
    final key = _key(username);
    if (users.containsKey(key)) throw AuthException('这个用户名已经被注册了');

    final user = AppUser(
      id: _newId(),
      username: username.trim(),
      createdAt: DateTime.now(),
    );
    users[key] = _Record(
      user,
      PasswordHash.create(password, iterations: iterations),
    );
    await _saveUsers(users);
    return _signIn(user);
  }

  @override
  Future<AppUser> login(String username, String password) async {
    final record = _loadUsers()[_key(username)];
    // 用户名不存在和密码错误给同一句提示，不暴露哪些用户名已注册。
    if (record == null || !record.password.verify(password)) {
      throw AuthException('用户名或密码不对');
    }
    return _signIn(record.user);
  }

  @override
  Future<void> logout() async {
    _current = null;
    await _prefs.remove(_sessionKey);
    notifyListeners();
  }

  @override
  Future<AppUser> updatePreferences(UserPreferences preferences) async {
    final current = _current;
    if (current == null) throw AuthException('请先登录');
    final users = _loadUsers();
    final key = _key(current.username);
    final record = users[key]!;
    final updated = current.copyWith(preferences: preferences);
    users[key] = _Record(updated, record.password);
    await _saveUsers(users);
    _current = updated;
    notifyListeners();
    return updated;
  }

  Future<AppUser> _signIn(AppUser user) async {
    _current = user;
    await _prefs.setString(_sessionKey, user.id);
    notifyListeners();
    return user;
  }

  String? _findNameById(String id) {
    for (final e in _loadUsers().entries) {
      if (e.value.user.id == id) return e.key;
    }
    return null;
  }

  Map<String, _Record> _loadUsers() {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, _Record.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsers(Map<String, _Record> users) => _prefs.setString(
      _usersKey, jsonEncode(users.map((k, v) => MapEntry(k, v.toJson()))));

  static String _newId() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(36).toRadixString(36)).join();
  }
}

class _Record {
  _Record(this.user, this.password);
  final AppUser user;
  final PasswordHash password;

  Map<String, dynamic> toJson() => {
        'id': user.id,
        'username': user.username,
        'createdAt': user.createdAt.toIso8601String(),
        'preferences': user.preferences.toJson(),
        'password': password.toJson(),
      };

  factory _Record.fromJson(Map<String, dynamic> json) => _Record(
        AppUser(
          id: json['id'] as String,
          username: json['username'] as String,
          createdAt: DateTime.parse(json['createdAt'] as String),
          preferences: UserPreferences.fromJson(
              (json['preferences'] as Map<String, dynamic>?) ?? const {}),
        ),
        PasswordHash.fromJson(json['password'] as Map<String, dynamic>),
      );
}
