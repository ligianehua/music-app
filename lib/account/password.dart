import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 加盐、多轮哈希后的密码。只存这个，永远不存明文。
class PasswordHash {
  const PasswordHash({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  final String salt;
  final String hash;
  final int iterations;

  /// 迭代次数。越大越难暴力破解，也越慢；这个值在手机上约几十毫秒。
  static const defaultIterations = 20000;

  static PasswordHash create(String password,
      {int iterations = defaultIterations, Random? random}) {
    final rng = random ?? Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => rng.nextInt(256)));
    return PasswordHash(
      salt: salt,
      iterations: iterations,
      hash: base64Url.encode(_pbkdf2(password, salt, iterations)),
    );
  }

  bool verify(String password) {
    final candidate = _pbkdf2(password, salt, iterations);
    final expected = base64Url.decode(hash);
    // 逐字节比较完再出结果，避免按耗时猜出前缀。
    if (candidate.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate[i] ^ expected[i];
    }
    return diff == 0;
  }

  Map<String, dynamic> toJson() =>
      {'salt': salt, 'hash': hash, 'iterations': iterations};

  factory PasswordHash.fromJson(Map<String, dynamic> json) => PasswordHash(
        salt: json['salt'] as String,
        hash: json['hash'] as String,
        iterations: (json['iterations'] as num).toInt(),
      );
}

/// PBKDF2-HMAC-SHA256，输出 32 字节。
Uint8List _pbkdf2(String password, String salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(password));
  // 只需要一个块：32 字节正好是 SHA-256 的输出长度。
  final block = Uint8List.fromList([...utf8.encode(salt), 0, 0, 0, 1]);
  var u = Uint8List.fromList(hmac.convert(block).bytes);
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}
