import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../recommend/taste_profile.dart';

/// 一个账号在本机的个人数据：点赞、收藏、口味画像、搜索历史。
///
/// 所有键都带上用户 id 前缀，同一台手机上的不同账号互不影响。
class LibraryStore {
  LibraryStore(this._prefs, {required this.userId});

  static Future<LibraryStore> open(String userId) async =>
      LibraryStore(await SharedPreferences.getInstance(), userId: userId);

  final SharedPreferences _prefs;
  final String userId;

  String _k(String name) => 'u:$userId:$name';

  /// 搜索历史最多保留多少条。
  static const maxHistory = 20;

  List<Track> _loadTracks(String name) {
    final raw = _prefs.getString(_k(name));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveTracks(String name, List<Track> tracks) => _prefs.setString(
      _k(name), jsonEncode(tracks.map((t) => t.toJson()).toList()));

  /// 点赞过的歌，新的在前。
  List<Track> loadLiked() => _loadTracks('liked');
  Future<void> saveLiked(List<Track> tracks) => _saveTracks('liked', tracks);

  /// 收藏的歌，新的在前。
  List<Track> loadFavorites() => _loadTracks('favorites');
  Future<void> saveFavorites(List<Track> tracks) =>
      _saveTracks('favorites', tracks);

  TasteProfile loadProfile() {
    final raw = _prefs.getString(_k('profile'));
    if (raw == null) return TasteProfile();
    try {
      return TasteProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return TasteProfile();
    }
  }

  Future<void> saveProfile(TasteProfile p) =>
      _prefs.setString(_k('profile'), jsonEncode(p.toJson()));

  /// 清空口味画像，重新冷启动。
  Future<void> resetProfile() => _prefs.remove(_k('profile'));

  /// 搜索历史，新的在前。
  List<String> loadSearchHistory() =>
      _prefs.getStringList(_k('search_history')) ?? [];

  /// 记一条搜索：去重后放到最前面。
  Future<List<String>> addSearch(String term) async {
    final t = term.trim();
    final list = loadSearchHistory();
    if (t.isEmpty) return list;
    list
      ..remove(t)
      ..insert(0, t);
    if (list.length > maxHistory) list.removeRange(maxHistory, list.length);
    await _prefs.setStringList(_k('search_history'), list);
    return list;
  }

  Future<void> clearSearchHistory() => _prefs.remove(_k('search_history'));
}
