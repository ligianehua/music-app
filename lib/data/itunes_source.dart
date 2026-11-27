import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'track_source.dart';

/// 基于 iTunes Search API 的音源。免费、无需密钥，每首歌带 30 秒试听。
///
/// 文档：https://performance-partners.apple.com/search-api
class ItunesSource implements TrackSource {
  ItunesSource({http.Client? client, this.country = 'cn'})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 商店区域。`cn` 区华语曲目多，换成 `us` 等可以刷欧美。
  final String country;

  @override
  Future<List<Track>> search(String term, {int limit = 30}) async {
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
      throw TrackSourceException('网络超时，下拉重试一下');
    } catch (e) {
      throw TrackSourceException('网络不可用：$e');
    }
    if (res.statusCode != 200) {
      throw TrackSourceException('曲库接口返回 ${res.statusCode}');
    }
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
  }
}
