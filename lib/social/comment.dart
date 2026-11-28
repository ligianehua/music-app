import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../account/user.dart';

/// 一条评论。
class Comment {
  const Comment({
    required this.id,
    required this.trackId,
    required this.userId,
    required this.username,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String trackId;
  final String userId;
  final String username;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'userId': userId,
        'username': username,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 评论仓库。现在存在本机，以后接服务器只需要换实现。
abstract class CommentStore {
  /// 某首歌的评论，新的在前。
  Future<List<Comment>> list(String trackId);

  Future<Comment> add(String trackId, AppUser author, String text);

  /// 只能删自己的评论，删别人的会抛 [StateError]。
  Future<void> delete(Comment comment, AppUser by);
}

/// 评论最长字数。
const maxCommentLength = 300;

/// 本机评论：同一台手机上的所有账号互相可见，换手机就看不到。
class LocalCommentStore implements CommentStore {
  LocalCommentStore(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  static const _key = 'comments_v1';

  Map<String, List<Comment>> _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(
          k,
          (v as List)
              .cast<Map<String, dynamic>>()
              .map(Comment.fromJson)
              .toList()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, List<Comment>> all) => _prefs.setString(
      _key,
      jsonEncode(all.map(
          (k, v) => MapEntry(k, [for (final c in v) c.toJson()]))));

  @override
  Future<List<Comment>> list(String trackId) async {
    final list = [...?_load()[trackId]]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<Comment> add(String trackId, AppUser author, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('评论不能为空');
    if (trimmed.length > maxCommentLength) {
      throw ArgumentError('评论最多 $maxCommentLength 字');
    }
    final rng = Random.secure();
    final comment = Comment(
      id: List.generate(12, (_) => rng.nextInt(36).toRadixString(36)).join(),
      trackId: trackId,
      userId: author.id,
      username: author.username,
      text: trimmed,
      createdAt: _clock(),
    );
    final all = _load();
    (all[trackId] ??= []).add(comment);
    await _save(all);
    return comment;
  }

  @override
  Future<void> delete(Comment comment, AppUser by) async {
    if (comment.userId != by.id) throw StateError('只能删除自己的评论');
    final all = _load();
    all[comment.trackId]?.removeWhere((c) => c.id == comment.id);
    await _save(all);
  }
}
