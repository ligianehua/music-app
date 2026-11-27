import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../recommend/taste_profile.dart';

/// 本机存储：红心歌单、口味画像、本地评论。纯前端 Demo 不上传任何数据。
class LibraryStore {
  LibraryStore(this._prefs);

  static Future<LibraryStore> open() async =>
      LibraryStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _likedKey = 'liked_tracks';
  static const _profileKey = 'taste_profile';
  static const _notesKey = 'track_notes';

  List<Track> loadLiked() {
    final raw = _prefs.getString(_likedKey);
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

  Future<void> saveLiked(List<Track> tracks) => _prefs.setString(
      _likedKey, jsonEncode(tracks.map((t) => t.toJson()).toList()));

  TasteProfile loadProfile() {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return TasteProfile();
    try {
      return TasteProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return TasteProfile();
    }
  }

  Future<void> saveProfile(TasteProfile p) =>
      _prefs.setString(_profileKey, jsonEncode(p.toJson()));

  Map<String, List<String>> loadNotes() {
    final raw = _prefs.getString(_notesKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<String>()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveNotes(Map<String, List<String>> notes) =>
      _prefs.setString(_notesKey, jsonEncode(notes));

  /// 清空口味画像，重新冷启动。
  Future<void> resetProfile() => _prefs.remove(_profileKey);
}
