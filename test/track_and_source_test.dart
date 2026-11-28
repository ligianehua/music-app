import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuage/data/itunes_source.dart';
import 'package:shuage/data/track_source.dart';
import 'package:shuage/models/track.dart';

Map<String, dynamic> itunesSong(int id,
        {String kind = 'song', String? preview = 'https://a/p.m4a'}) =>
    {
      'kind': kind,
      'trackId': id,
      'trackName': '晴天',
      'artistName': '周杰伦',
      'collectionName': '叶惠美',
      'artworkUrl100': 'https://img/x/100x100bb.jpg',
      'previewUrl': preview,
      'primaryGenreName': 'Mandopop',
      'trackTimeMillis': 269000,
      'trackViewUrl': 'https://music.apple.com/x',
    };

/// 带中文的 JSON 响应要按 UTF-8 字节构造。
http.Response json200(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  group('Track', () {
    test('fromItunes upscales artwork and maps fields', () {
      final t = Track.fromItunes(itunesSong(42));
      expect(t.id, 'itunes:42');
      expect(t.title, '晴天');
      expect(t.artist, '周杰伦');
      expect(t.artworkUrl, 'https://img/x/600x600bb.jpg');
      expect(t.durationMs, 269000);
      expect(t.genre, 'Mandopop');
    });

    test('json round trip keeps every field', () {
      final t = Track.fromItunes(itunesSong(7));
      final back = Track.fromJson(jsonDecode(jsonEncode(t.toJson())));
      expect(back.toJson(), t.toJson());
      expect(back, t);
    });
  });

  group('ItunesSource', () {
    test('builds the query and keeps only playable songs', () async {
      late Uri seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'results': [
              itunesSong(1),
              itunesSong(2, kind: 'music-video'),
              itunesSong(3, preview: null),
              itunesSong(4, preview: ''),
              itunesSong(5),
            ],
          })),
          200,
        );
      });
      final tracks = await ItunesSource(client: client, storefronts: ['hk'])
          .search('周杰伦', limit: 5);
      expect(tracks.map((t) => t.id), ['itunes:1', 'itunes:5']);
      expect(seen.host, 'itunes.apple.com');
      expect(seen.queryParameters, {
        'term': '周杰伦',
        'entity': 'song',
        'limit': '5',
        'country': 'hk',
      });
    });

    test('never queries the China storefront by default', () {
      // iTunes 中国区不卖单曲，按歌曲搜索永远是空列表。
      expect(ItunesSource.defaultStorefronts, isNot(contains('cn')));
    });

    test('falls through storefronts until one has playable songs', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        final country = req.url.queryParameters['country']!;
        asked.add(country);
        final results = country == 'us' ? [itunesSong(9)] : [];
        return json200({'results': results});
      });
      final tracks = await ItunesSource(client: client).search('x');
      expect(asked, ['hk', 'tw', 'us']);
      expect(tracks.single.id, 'itunes:9');
    });

    test('stops at the first storefront with results', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.queryParameters['country']!);
        return json200({'results': [itunesSong(1)]});
      });
      await ItunesSource(client: client).search('x');
      expect(asked, ['hk']);
    });

    test('an error in one storefront does not hide results from the next', () async {
      final client = MockClient((req) async =>
          req.url.queryParameters['country'] == 'hk'
              ? http.Response('busy', 503)
              : json200({'results': [itunesSong(2)]}));
      final tracks = await ItunesSource(client: client).search('x');
      expect(tracks.single.id, 'itunes:2');
    });

    test('an HTML page instead of JSON becomes a readable error', () async {
      final client = MockClient(
          (_) async => http.Response('<html>login to wifi</html>', 200));
      expect(
        () => ItunesSource(client: client).search('x'),
        throwsA(isA<TrackSourceException>()
            .having((e) => e.message, 'message', contains('无法识别'))),
      );
    });

    test('throws a readable error on HTTP failure', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => ItunesSource(client: client).search('x'),
        throwsA(isA<TrackSourceException>()
            .having((e) => e.message, 'message', contains('503'))),
      );
    });

    test('wraps network exceptions', () async {
      final client = MockClient((_) async => throw http.ClientException('down'));
      expect(() => ItunesSource(client: client).search('x'),
          throwsA(isA<TrackSourceException>()));
    });

    test('returns empty list for unexpected payloads', () async {
      final client = MockClient((_) async => http.Response('{"oops":1}', 200));
      expect(await ItunesSource(client: client).search('x'), isEmpty);
    });
  });
}
