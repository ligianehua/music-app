import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 用户校准过的歌词偏移：试听片段第 0 秒对应原曲的哪个时刻。
///
/// 偏移是试听片段本身的属性，和谁在听无关，所以整台手机共用，不按账号分。
class LyricsOffsetStore {
  LyricsOffsetStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'lyrics_offsets_v1';

  /// 最多记多少首，超出时丢掉最早校准的。
  static const maxEntries = 500;

  Map<String, int> _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Duration? get(String trackId) {
    final ms = _load()[trackId];
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<void> set(String trackId, Duration offset) async {
    // 先删再加：最近校准的排在最后，裁剪时从最早的开始丢。
    final all = _load()
      ..remove(trackId)
      ..[trackId] = offset.inMilliseconds;
    while (all.length > maxEntries) {
      all.remove(all.keys.first);
    }
    await _prefs.setString(_key, jsonEncode(all));
  }
}
