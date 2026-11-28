import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../lyrics/lrc.dart';
import '../models/track.dart';

/// 歌词来源。
abstract class LyricsSource {
  /// 找不到或网络失败时返回 null，歌词缺失不应该打断刷歌。
  Future<Lyrics?> fetch(Track track);
}

/// LRCLIB：免费、开源、无需密钥的歌词库。https://lrclib.net/docs
class LrclibSource implements LyricsSource {
  LrclibSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, Future<Lyrics?>> _cache = {};

  @override
  Future<Lyrics?> fetch(Track track) =>
      _cache.putIfAbsent(track.id, () => _fetch(track));

  Future<Lyrics?> _fetch(Track track) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': track.title,
      'artist_name': track.artist,
    });
    try {
      final res = await _client.get(uri, headers: const {
        'User-Agent': 'shuage-demo/0.1',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List || list.isEmpty) return null;
      final candidates = list.whereType<Map<String, dynamic>>().toList();
      return pickBestLyrics(candidates, track);
    } catch (_) {
      return null;
    }
  }
}

/// 从 LRCLIB 的候选里挑一条：优先有时间轴的，其次时长最接近的。
Lyrics? pickBestLyrics(List<Map<String, dynamic>> candidates, Track track) {
  if (candidates.isEmpty) return null;
  final targetSec = track.durationMs / 1000;
  double distance(Map<String, dynamic> c) {
    final d = (c['duration'] as num?)?.toDouble();
    if (d == null || targetSec == 0) return 0;
    return (d - targetSec).abs();
  }

  int hasSynced(Map<String, dynamic> c) =>
      (c['syncedLyrics'] as String?)?.isNotEmpty == true ? 0 : 1;

  final sorted = [...candidates]..sort((a, b) {
      final s = hasSynced(a).compareTo(hasSynced(b));
      return s != 0 ? s : distance(a).compareTo(distance(b));
    });
  final best = sorted.first;
  final synced = best['syncedLyrics'] as String?;
  final plain = best['plainLyrics'] as String?;
  final lyrics = Lyrics(
    synced: synced == null || synced.isEmpty ? null : parseLrc(synced),
    plain: (plain ?? '')
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(),
  );
  return lyrics.isEmpty ? null : lyrics;
}
