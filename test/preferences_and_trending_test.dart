import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuage/account/user.dart';
import 'package:shuage/data/trending_source.dart';
import 'package:shuage/models/track.dart';
import 'package:shuage/recommend/preference_options.dart';
import 'package:shuage/recommend/recommender.dart';
import 'package:shuage/recommend/taste_profile.dart';

import 'fakes.dart';

http.Response json200(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

class FakeTrending implements TrendingSource {
  FakeTrending(this.tracks);
  final List<Track> tracks;
  int calls = 0;
  @override
  Future<List<Track>> trending() async {
    calls++;
    return tracks;
  }
}

void main() {
  group('preferenceSeeds', () {
    test('artists come through as-is', () {
      expect(preferenceSeeds(const UserPreferences(artists: {'陈奕迅'})), ['陈奕迅']);
    });

    test('language + genre become search phrases per catalog', () {
      final seeds = preferenceSeeds(const UserPreferences(
        languages: {'Filipino', 'English', 'Japanese'},
        genres: {'Rock'},
      ));
      expect(seeds, containsAll(['OPM rock', 'rock', 'J-rock']));
    });

    test('a language without genres uses its default term', () {
      expect(preferenceSeeds(const UserPreferences(languages: {'Filipino', 'Korean'})),
          ['OPM', 'K-Pop']);
    });

    test('genres without language are searched directly', () {
      expect(preferenceSeeds(const UserPreferences(genres: {'Acoustic'})), ['acoustic']);
    });

    test('artist options follow the chosen languages without duplicates', () {
      final opm = artistOptionsFor({'Filipino'});
      expect(opm, contains('Ben&Ben'));
      expect(opm, isNot(contains('Taylor Swift')));
      final all = artistOptionsFor({});
      expect(all.toSet().length, all.length);
    });
  });

  group('Recommender with preferences', () {
    test('cold start explores mostly within the chosen preferences', () async {
      final source = FakeSource({}, fallback: [track('1')]);
      final rec = Recommender(
        source: source,
        profile: TasteProfile(),
        preferences: const UserPreferences(languages: {'Filipino'}),
        seeds: ['default-seed'],
        random: Random(3),
      );
      for (var i = 0; i < 20; i++) {
        await rec.nextBatch(size: 1);
      }
      final preferred = source.terms.where((t) => t == 'OPM').length;
      expect(preferred, greaterThan(source.terms.length ~/ 2));
      expect(source.terms, contains('default-seed'), reason: '仍留一部分探索，防止越推越窄');
    });

    test('chosen artists are exploited with a "You picked" reason', () async {
      final source = FakeSource({'周杰伦': [track('1', artist: '周杰伦')]});
      final rec = Recommender(
        source: source,
        profile: TasteProfile(),
        preferences: const UserPreferences(artists: {'周杰伦'}),
        exploreRatio: 0,
        seeds: ['x'],
      );
      final batch = await rec.nextBatch();
      expect(batch.single.reason, 'You picked 周杰伦');
    });

    test('searched terms are exploited with a "Because you searched" reason', () async {
      final profile = TasteProfile()..recordSearch('后摇');
      final source = FakeSource({'后摇': [track('1', artist: 'Mogwai')]});
      final rec = Recommender(
          source: source, profile: profile, exploreRatio: 0, seeds: ['x']);
      final batch = await rec.nextBatch();
      expect(batch.single.reason, 'Because you searched 后摇');
    });

    test('blocked artists are never chosen even if picked in preferences', () async {
      final profile = TasteProfile()..record(track('0', artist: '周杰伦'), Signal.dislike);
      final source = FakeSource({}, fallback: [track('1', artist: 'Ok')]);
      final rec = Recommender(
        source: source,
        profile: profile,
        preferences: const UserPreferences(artists: {'周杰伦'}),
        seeds: ['seed'],
      );
      for (var i = 0; i < 10; i++) {
        await rec.nextBatch(size: 1);
      }
      expect(source.terms, isNot(contains('周杰伦')));
    });

    test('viral fans get batches from the trending chart', () async {
      final trending = FakeTrending([track('hot1', artist: 'H1'), track('hot2', artist: 'H2')]);
      final rec = Recommender(
        source: FakeSource({}),
        profile: TasteProfile(),
        preferences: const UserPreferences(viral: true),
        trending: trending,
        viralRatio: 1,
        seeds: ['s'],
      );
      final batch = await rec.nextBatch();
      expect(batch.map((r) => r.track.id).toSet(), {'hot1', 'hot2'});
      expect(batch.first.reason, 'Top charts');
    });

    test('an empty chart falls back to searching viral artists', () async {
      final source = FakeSource({}, fallback: [track('v', artist: 'V')]);
      final rec = Recommender(
        source: source,
        profile: TasteProfile(),
        preferences: const UserPreferences(viral: true),
        trending: FakeTrending([]),
        viralRatio: 1,
        seeds: ['s'],
      );
      final batch = await rec.nextBatch();
      expect(viralFallbackArtists, contains(source.terms.single));
      expect(batch.single.reason, startsWith('Trending: '));
    });

    test('people who did not opt in never get the chart', () async {
      final trending = FakeTrending([track('hot')]);
      final rec = Recommender(
        source: FakeSource({}, fallback: [track('1')]),
        profile: TasteProfile(),
        trending: trending,
        viralRatio: 1,
        seeds: ['s'],
      );
      await rec.nextBatch();
      expect(trending.calls, 0);
    });
  });

  group('AppleChartSource', () {
    Map<String, dynamic> song(int id) => {
          'kind': 'song',
          'trackId': id,
          'trackName': '热歌$id',
          'artistName': '歌手$id',
          'artworkUrl100': 'https://a/100x100bb.jpg',
          'previewUrl': 'https://a/$id.m4a',
        };

    test('reads chart ids, then looks up playable songs in chart order', () async {
      final asked = <Uri>[];
      final client = MockClient((req) async {
        asked.add(req.url);
        if (req.url.host == 'rss.applemarketingtools.com') {
          return json200({
            'feed': {
              'results': [
                {'id': '3'}, {'id': '1'}, {'id': '2'},
              ],
            },
          });
        }
        // 查询接口返回顺序和榜单不同，其中 2 没有试听。
        return json200({
          'results': [song(1), song(3), {...song(2), 'previewUrl': null}],
        });
      });
      final chart = AppleChartSource(client: client, storefronts: ['hk']);
      final tracks = await chart.trending();
      expect(tracks.map((t) => t.id), ['itunes:3', 'itunes:1']);
      expect(asked.first.path, '/api/v2/hk/music/most-played/50/songs.json');
      expect(asked.last.queryParameters['id'], '3,1,2');
      expect(asked.last.queryParameters['country'], 'hk');
    });

    test('caches for a while, then refreshes', () async {
      var calls = 0;
      var now = DateTime(2026, 11, 28, 12);
      final client = MockClient((req) async {
        calls++;
        return req.url.host == 'rss.applemarketingtools.com'
            ? json200({'feed': {'results': [{'id': '1'}]}})
            : json200({'results': [song(1)]});
      });
      final chart = AppleChartSource(
          client: client, storefronts: ['hk'], clock: () => now);
      await chart.trending();
      await chart.trending();
      expect(calls, 2);
      now = now.add(AppleChartSource.cacheFor);
      await chart.trending();
      expect(calls, 4);
    });

    test('never throws; a broken storefront is skipped', () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('/hk/')) return http.Response('down', 503);
        return req.url.host == 'rss.applemarketingtools.com'
            ? json200({'feed': {'results': [{'id': '7'}]}})
            : json200({'results': [song(7)]});
      });
      final tracks =
          await AppleChartSource(client: client, storefronts: ['hk', 'tw']).trending();
      expect(tracks.single.id, 'itunes:7');
      final dead = MockClient((_) async => throw http.ClientException('offline'));
      expect(await AppleChartSource(client: dead).trending(), isEmpty);
    });
  });
}
