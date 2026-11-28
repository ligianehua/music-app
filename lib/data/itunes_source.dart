import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'track_source.dart';

/// 基于 iTunes Search API 的音源。免费、无需密钥，每首歌带 30 秒试听。
///
/// 文档：https://performance-partners.apple.com/search-api
class ItunesSource implements TrackSource {
  ItunesSource({http.Client? client, this.storefronts = defaultStorefronts})
      : assert(storefronts.isNotEmpty),
        _client = client ?? http.Client();

  /// 默认依次查询的商店区域：先菲律宾区，再美区。
  ///
  /// 美区曲目最全，基本覆盖全球；菲律宾区补本地歌手。前一个区搜不到就换下一个。
  /// 不能用中国区 `cn`：iTunes 中国区从不卖单曲，按歌曲搜索永远返回空列表。
  static const defaultStorefronts = ['ph', 'us'];

  final http.Client _client;
  final List<String> storefronts;

  /// 按顺序在各区搜索，返回第一个有可播结果的区的结果。
  @override
  Future<List<Track>> search(String term, {int limit = 30}) async {
    TrackSourceException? lastError;
    for (final country in storefronts) {
      try {
        final found = await _searchIn(country, term, limit);
        if (found.isNotEmpty) return found;
      } on TrackSourceException catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }

  Future<List<Track>> _searchIn(String country, String term, int limit) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'song',
      'limit': '$limit',
      'country': country,
    });
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw TrackSourceException('The connection timed out. Please try again.');
    } catch (e) {
      throw TrackSourceException('No internet connection.');
    }
    if (res.statusCode != 200) {
      throw TrackSourceException('The music service is unavailable (error ${res.statusCode}).');
    }
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final results = body is Map<String, dynamic> ? body['results'] : null;
      if (results is! List) return const [];
      return results
          .whereType<Map<String, dynamic>>()
          .where((j) =>
              j['kind'] == 'song' &&
              (j['previewUrl'] as String?)?.isNotEmpty == true)
          .map(Track.fromItunes)
          .toList();
    } catch (_) {
      // 常见于网络被劫持、返回了一个网页而不是 JSON。
      throw TrackSourceException('The music service sent an unexpected response. Your network may be blocking it.');
    }
  }
}
