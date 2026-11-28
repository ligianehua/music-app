import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';

/// 热歌来源。
abstract class TrendingSource {
  /// 当前热门的歌。拉不到时返回空列表，不抛异常。
  Future<List<Track>> trending();
}

/// Apple Music 菲律宾区和美区的「最多播放」榜单。
///
/// TikTok 没有公开的热歌接口，这里用 Apple 的榜单近似「正在流行」：先取榜单上的歌曲 id，
/// 再用 iTunes 查询接口补上试听地址。结果在一次运行内缓存 30 分钟。
class AppleChartSource implements TrendingSource {
  AppleChartSource({
    http.Client? client,
    this.storefronts = const ['ph', 'us'],
    this.limit = 50,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final http.Client _client;
  final List<String> storefronts;
  final int limit;
  final DateTime Function() _clock;

  List<Track>? _cache;
  DateTime? _cachedAt;
  static const cacheFor = Duration(minutes: 30);

  @override
  Future<List<Track>> trending() async {
    final at = _cachedAt;
    if (_cache != null && at != null && _clock().difference(at) < cacheFor) {
      return _cache!;
    }
    final out = <Track>[];
    final ids = <String>{};
    for (final sf in storefronts) {
      try {
        for (final t in await _chart(sf)) {
          if (ids.add(t.id)) out.add(t);
        }
      } catch (_) {
        // 某个区拉不到就跳过，热歌只是锦上添花。
      }
    }
    if (out.isNotEmpty) {
      _cache = out;
      _cachedAt = _clock();
    }
    return out;
  }

  Future<List<Track>> _chart(String storefront) async {
    final chart = await _getJson(Uri.https('rss.applemarketingtools.com',
        '/api/v2/$storefront/music/most-played/$limit/songs.json'));
    final results = (chart['feed'] as Map<String, dynamic>?)?['results'];
    if (results is! List || results.isEmpty) return const [];
    final ids = [
      for (final r in results.whereType<Map<String, dynamic>>())
        if (r['id'] != null) '${r['id']}',
    ];
    if (ids.isEmpty) return const [];
    final lookup = await _getJson(Uri.https('itunes.apple.com', '/lookup', {
      'id': ids.join(','),
      'country': storefront,
      'entity': 'song',
    }));
    final songs = lookup['results'];
    if (songs is! List) return const [];
    final byId = {
      for (final s in songs.whereType<Map<String, dynamic>>())
        if (s['kind'] == 'song' &&
            (s['previewUrl'] as String?)?.isNotEmpty == true)
          '${s['trackId']}': Track.fromItunes(s),
    };
    // 保持榜单顺序。
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) throw const FormatException('not an object');
    return body;
  }
}
