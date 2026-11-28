import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/account/auth_service.dart';
import 'package:shuage/account/local_auth_service.dart';
import 'package:shuage/account/password.dart';
import 'package:shuage/account/user.dart';

void main() {
  group('PasswordHash', () {
    test('verifies the right password only', () {
      final h = PasswordHash.create('abc123', iterations: 50);
      expect(h.verify('abc123'), isTrue);
      expect(h.verify('abc124'), isFalse);
      expect(h.verify(''), isFalse);
    });

    test('salts differ, so the same password hashes differently', () {
      final a = PasswordHash.create('abc123', iterations: 50);
      final b = PasswordHash.create('abc123', iterations: 50);
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
    });

    test('matches the PBKDF2-HMAC-SHA256 reference vector', () {
      // RFC 7914 第 11 节：P="passwd"，S="salt"，c=1，取前 32 字节。
      final expected = PasswordHash(
        salt: 'salt',
        iterations: 1,
        hash: base64Url.encode(_hex(
            '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc')),
      );
      expect(expected.verify('passwd'), isTrue);
    });

    test('survives a json round trip', () {
      final h = PasswordHash.create('abc123', iterations: 50, random: Random(1));
      final back = PasswordHash.fromJson(jsonDecode(jsonEncode(h.toJson())));
      expect(back.verify('abc123'), isTrue);
    });
  });

  group('validation', () {
    test('username rules', () {
      expect(validateUsername('小明'), isNull);
      expect(validateUsername('jay_chou_88'), isNull);
      expect(validateUsername(''), isNotNull);
      expect(validateUsername('a'), isNotNull);
      expect(validateUsername('有 空格'), isNotNull);
      expect(validateUsername('x' * 21), isNotNull);
    });

    test('password rules', () {
      expect(validatePassword('abc123'), isNull);
      expect(validatePassword('ab12'), contains('6'));
      expect(validatePassword('abcdefg'), contains('数字'));
      expect(validatePassword('1234567'), contains('字母'));
    });
  });

  group('LocalAuthService', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    LocalAuthService service() => LocalAuthService(prefs, iterations: 10);

    test('register signs in and never stores the plain password', () async {
      final auth = service();
      var notified = 0;
      auth.addListener(() => notified++);
      final u = await auth.register(' 小明 ', 'abc123');
      expect(u.username, '小明');
      expect(auth.currentUser?.id, u.id);
      expect(u.needsOnboarding, isTrue);
      expect(notified, 1);
      final raw = prefs.getString('auth_users')!;
      expect(raw, isNot(contains('abc123')));
    });

    test('usernames are unique, ignoring case', () async {
      final auth = service();
      await auth.register('Jay', 'abc123');
      await auth.logout();
      expect(() => auth.register('jay', 'xyz789'),
          throwsA(isA<AuthException>()));
    });

    test('invalid input is rejected with a readable message', () async {
      final auth = service();
      expect(() => auth.register('a', 'abc123'),
          throwsA(isA<AuthException>().having((e) => e.message, 'm', contains('用户名'))));
      expect(() => auth.register('小明', '123'),
          throwsA(isA<AuthException>().having((e) => e.message, 'm', contains('密码'))));
    });

    test('login checks the password and does not reveal which part was wrong',
        () async {
      final auth = service();
      await auth.register('小明', 'abc123');
      await auth.logout();
      expect(auth.currentUser, isNull);
      Future<String> fail(String u, String p) =>
          auth.login(u, p).then((_) => 'ok', onError: (Object e) => '$e');
      expect(await fail('小明', 'wrong1'), '用户名或密码不对');
      expect(await fail('没这个人', 'abc123'), '用户名或密码不对');
      final u = await auth.login('小明', 'abc123');
      expect(auth.currentUser, same(u));
    });

    test('the session survives an app restart, logout ends it', () async {
      final u = await service().register('小明', 'abc123');
      final restarted = service();
      expect(restarted.currentUser?.id, u.id);
      await restarted.logout();
      expect(service().currentUser, isNull);
    });

    test('preferences are saved to the account', () async {
      final auth = service();
      await auth.register('小明', 'abc123');
      final updated = await auth.updatePreferences(
          const UserPreferences(languages: {'粤语'}, artists: {'陈奕迅'}, viral: true));
      expect(updated.needsOnboarding, isFalse);
      await auth.logout();
      final again = await service().login('小明', 'abc123');
      expect(again.preferences.languages, {'粤语'});
      expect(again.preferences.artists, {'陈奕迅'});
      expect(again.preferences.viral, isTrue);
    });

    test('updating preferences requires a signed-in user', () {
      expect(() => service().updatePreferences(const UserPreferences()),
          throwsA(isA<AuthException>()));
    });
  });
}

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
    ];
