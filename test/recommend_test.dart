import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuage/data/track_source.dart';
import 'package:shuage/recommend/recommender.dart';
import 'package:shuage/recommend/taste_profile.dart';

import 'fakes.dart';

void main() {
  group('signalForListen', () {
    const total = Duration(seconds: 30);
    test('maps listen ratio to signals', () {
      expect(signalForListen(const Duration(seconds: 3), total), Signal.quickSkip);
      expect(signalForListen(const Duration(seconds: 10), total), Signal.earlySkip);
      expect(signalForListen(const Duration(seconds: 20), total), Signal.lateSkip);
      expect(signalForListen(const Duration(seconds: 28), total), Signal.complete);
      expect(signalForListen(Duration.zero, Duration.zero), Signal.earlySkip);
    });
  });

  group('TasteProfile', () {
    test('artist gets full weight, genre half', () {
      final p = TasteProfile()..record(track('1', artist: 'X', genre: 'Rock'), Signal.like);
      expect(p.artists['X'], 2.0);
      expect(p.genres['Rock'], 1.0);
      expect(p.score(track('2', artist: 'X', genre: 'Rock')), 2.5);
    });

    test('like then unlike cancels out', () {
      final t = track('1', artist: 'X');
      final p = TasteProfile()
        ..record(t, Signal.like)
        ..record(t, Signal.unlike);
      expect(p.artists, isEmpty);
      expect(p.hasPreference, isFalse);
    });

    test('scores are clamped', () {
      final p = TasteProfile();
      for (var i = 0; i < 20; i++) {
        p.record(track('1', artist: 'X'), Signal.like);
      }
      expect(p.artists['X'], TasteProfile.maxScore);
    });

    test('dislike blocks the artist', () {
      final p = TasteProfile()..record(track('1', artist: 'X'), Signal.dislike);
      expect(p.isBlocked(track('9', artist: 'X')), isTrue);
      expect(p.score(track('9', artist: 'X')), double.negativeInfinity);
    });

    test('json round trip', () {
      final p = TasteProfile()
        ..record(track('1', artist: 'X', genre: 'G'), Signal.complete)
        ..record(track('2', artist: 'Y'), Signal.dislike);
      final back = TasteProfile.fromJson(p.toJson());
      expect(back.artists, p.artists);
      expect(back.genres, p.genres);
      expect(back.blockedArtists, {'Y'});
    });
  });

  group('Recommender', () {
    test('cold start explores seeds with a "热门推荐" reason', () async {
      final source = FakeSource({'s1': [track('1'), track('2', artist: 'B')]});
      final rec = Recommender(
          source: source, profile: TasteProfile(), seeds: ['s1']);
      final batch = await rec.nextBatch();
      expect(source.terms, ['s1']);
      expect(batch.map((r) => r.track.id), containsAll(['1', '2']));
      expect(batch.first.reason, '热门推荐：s1');
    });

    test('caps songs per artist and never repeats across batches', () async {
      final pool = [
        for (var i = 0; i < 6; i++) track('$i', artist: 'Same'),
        track('x', artist: 'Other'),
      ];
      final rec = Recommender(
        source: FakeSource({}, fallback: pool),
        profile: TasteProfile(),
        seeds: ['s'],
        maxPerArtist: 2,
      );
      final a = await rec.nextBatch();
      expect(a.where((r) => r.track.artist == 'Same'), hasLength(2));
      final b = await rec.nextBatch();
      final ids = {...a.map((r) => r.track.id)};
      expect(b.every((r) => !ids.contains(r.track.id)), isTrue);
    });

    test('exploits liked artists when explore ratio is zero', () async {
      final profile = TasteProfile()..record(track('0', artist: '陈奕迅'), Signal.like);
      final source = FakeSource({'陈奕迅': [track('1', artist: '陈奕迅')]});
      final rec = Recommender(
        source: source,
        profile: profile,
        exploreRatio: 0,
        seeds: ['seed'],
        random: Random(1),
      );
      final batch = await rec.nextBatch();
      expect(source.terms, ['陈奕迅']);
      expect(batch.single.reason, '因为你常听 陈奕迅');
    });

    test('always explores when explore ratio is one', () async {
      final profile = TasteProfile()..record(track('0', artist: 'X'), Signal.like);
      final source = FakeSource({'seed': [track('1', artist: 'Y')]});
      final rec = Recommender(
          source: source, profile: profile, exploreRatio: 1, seeds: ['seed']);
      final batch = await rec.nextBatch();
      expect(source.terms, ['seed']);
      expect(batch.single.reason, '换换口味：seed');
    });

    test('filters blocked artists', () async {
      final profile = TasteProfile()..record(track('0', artist: 'Bad'), Signal.dislike);
      final rec = Recommender(
        source: FakeSource({}, fallback: [track('1', artist: 'Bad'), track('2', artist: 'Ok')]),
        profile: profile,
        seeds: ['s'],
      );
      final batch = await rec.nextBatch();
      expect(batch.map((r) => r.track.artist), ['Ok']);
    });

    test('retries with another term after an error', () async {
      final source = FakeSource({}, fallback: [track('1')])
        ..throwOnce = TrackSourceException('flaky');
      final rec = Recommender(source: source, profile: TasteProfile(), seeds: ['s']);
      final batch = await rec.nextBatch();
      expect(source.terms, hasLength(2));
      expect(batch, hasLength(1));
    });

    test('rethrows when every attempt fails', () async {
      final rec = Recommender(source: FailingSource(), profile: TasteProfile(), seeds: ['s']);
      expect(rec.nextBatch(), throwsA(isA<TrackSourceException>()));
    });
  });
}
