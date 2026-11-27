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
      final tracks = await ItunesSource(client: client, country: 'cn')
          .search('周杰伦', limit: 5);
      expect(tracks.map((t) => t.id), ['itunes:1', 'itunes:5']);
      expect(seen.host, 'itunes.apple.com');
      expect(seen.queryParameters, {
        'term': '周杰伦',
        'entity': 'song',
        'limit': '5',
        'country': 'cn',
      });
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
