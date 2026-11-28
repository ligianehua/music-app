import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuage/data/track_source.dart';
import 'package:shuage/models/track.dart';
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
    test('cold start explores seeds with a "Popular" reason', () async {
      final source = FakeSource({'s1': [track('1'), track('2', artist: 'B')]});
      final rec = Recommender(
          source: source, profile: TasteProfile(), seeds: ['s1']);
      final batch = await rec.nextBatch();
      expect(source.terms, ['s1']);
      expect(batch.map((r) => r.track.id), containsAll(['1', '2']));
      expect(batch.first.reason, 'Popular: s1');
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
      expect(batch.single.reason, 'Because you play 陈奕迅');
    });

    test('always explores when explore ratio is one', () async {
      final profile = TasteProfile()..record(track('0', artist: 'X'), Signal.like);
      final source = FakeSource({'seed': [track('1', artist: 'Y')]});
      final rec = Recommender(
          source: source, profile: profile, exploreRatio: 1, seeds: ['seed']);
      final batch = await rec.nextBatch();
      expect(source.terms, ['seed']);
      expect(batch.single.reason, 'Something new: seed');
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
  
    group('reserve', () {
      List<Track> pool(String prefix, int n) =>
          [for (var i = 0; i < n; i++) track('$prefix$i', artist: '$prefix$i')];

      test('leftovers from a search are kept as reserve', () async {
        final rec = Recommender(
          source: FakeSource({}, fallback: pool('x', 20)),
          profile: TasteProfile(),
          seeds: ['s'],
        );
        final batch = await rec.nextBatch(size: 8);
        expect(batch, hasLength(8));
        expect(rec.reserveSize, 12);
      });

      test('network error falls back to reserve immediately', () async {
        final source = FlakySource(0, pool('x', 20));
        final rec = Recommender(source: source, profile: TasteProfile(), seeds: ['s']);
        final first = await rec.nextBatch(size: 8);
        source.failures = 99;
        final second = await rec.nextBatch(size: 8);
        expect(second, hasLength(8));
        // 不和第一批重复，理由沿用当初的搜索词。
        final firstIds = {for (final r in first) r.track.id};
        expect(second.every((r) => !firstIds.contains(r.track.id)), isTrue);
        expect(second.first.reason, 'Popular: s');
        expect(source.failures, 98, reason: '有备用时网络出错不再重试');
      });

      test('empty search results fall back to reserve', () async {
        final source = SequenceSource([pool('x', 20)]); // 之后都返回空
        final rec = Recommender(source: source, profile: TasteProfile(), seeds: ['s']);
        await rec.nextBatch(size: 8);
        final second = await rec.nextBatch(size: 8);
        expect(second, hasLength(8));
      });

      test('reserve skips artists blocked after it was stashed', () async {
        final source = FlakySource(0, [
          for (var i = 0; i < 4; i++) track('ok$i', artist: 'Ok$i'),
          for (var i = 0; i < 6; i++) track('bad$i', artist: 'Bad'),
        ]);
        final profile = TasteProfile();
        final rec = Recommender(
            source: source, profile: profile, seeds: ['s'], maxPerArtist: 1);
        await rec.nextBatch(size: 2);
        profile.record(track('z', artist: 'Bad'), Signal.dislike);
        source.failures = 99;
        final batch = await rec.nextBatch(size: 8);
        expect(batch.every((r) => r.track.artist != 'Bad'), isTrue);
      });

      test('throws only when both network and reserve are empty', () async {
        final rec = Recommender(source: FailingSource(), profile: TasteProfile(), seeds: ['s']);
        expect(rec.nextBatch(), throwsA(isA<TrackSourceException>()));
      });

      test('reserve is capped', () async {
        final source = SequenceSource([
          for (var b = 0; b < 4; b++) pool('b${b}_', 30),
        ]);
        final rec = Recommender(source: source, profile: TasteProfile(), seeds: ['s']);
        for (var b = 0; b < 4; b++) {
          await rec.nextBatch(size: 2);
        }
        expect(rec.reserveSize, Recommender.maxReserve);
      });
    });
  });
}
