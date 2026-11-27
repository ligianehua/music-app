import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuage/feed/feed_controller.dart';
import 'package:shuage/recommend/recommender.dart';
import 'package:shuage/recommend/taste_profile.dart';

import 'fakes.dart';

/// 让排队的微任务和异步回调都跑完。
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudio audio;
  late FeedController c;

  Future<FeedController> build(List<String> artists,
      {bool autoAdvance = true}) async {
    audio = FakeAudio();
    var n = 0;
    final source = FakeSource({}, fallback: [
      for (final a in artists) track('t${n++}', artist: a),
    ]);
    c = FeedController(
      recommender: Recommender(
        source: source,
        profile: TasteProfile(),
        seeds: ['seed'],
        maxPerArtist: 99,
        exploreRatio: 1,
      ),
      audio: audio,
      store: await memoryStore(),
      autoAdvance: autoAdvance,
      prefetchThreshold: 0,
    );
    return c;
  }

  test('init loads a batch, plays the first and preloads the second', () async {
    await build(['A', 'B', 'C']);
    await c.init();
    await settle();
    expect(c.items, hasLength(3));
    expect(audio.played, [c.items[0].track.id]);
    expect(audio.preloaded, [c.items[1].track.id]);
    expect(c.playing.value, isTrue);
  });

  test('quick swipe records a negative signal for the artist', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final first = c.items[0].track;
    audio.tick(const Duration(seconds: 2));
    await c.onPageChanged(1);
    expect(c.profile.artists[first.artist], signalWeights[Signal.quickSkip]);
    expect(audio.played, [first.id, c.items[1].track.id]);
  });

  test('listening past half before swiping is a mild positive', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final first = c.items[0].track;
    audio.tick(const Duration(seconds: 20));
    await c.onPageChanged(1);
    expect(c.profile.artists[first.artist], signalWeights[Signal.lateSkip]);
  });

  test('seeking forward counts as listened', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final first = c.items[0].track;
    await c.seek(const Duration(seconds: 28));
    await c.onPageChanged(1);
    expect(c.profile.artists[first.artist], signalWeights[Signal.complete]);
  });

  test('completion records once and requests the next page', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final requests = <int>[];
    final sub = c.advanceRequests.listen(requests.add);
    audio.complete();
    audio.complete(); // 重复事件不应重复计分。
    await settle();
    expect(requests, [1]);
    final first = c.items[0].track;
    await c.onPageChanged(1);
    expect(c.profile.artists[first.artist], signalWeights[Signal.complete]);
    await sub.cancel();
  });

  test('no auto advance when disabled', () async {
    await build(['A', 'B'], autoAdvance: false);
    await c.init();
    await settle();
    final requests = <int>[];
    final sub = c.advanceRequests.listen(requests.add);
    audio.complete();
    await settle();
    expect(requests, isEmpty);
    await sub.cancel();
  });

  test('swiping back to a played song counts as replay', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final first = c.items[0].track;
    audio.tick(const Duration(seconds: 29));
    await c.onPageChanged(1);
    audio.tick(const Duration(seconds: 29));
    await c.onPageChanged(0);
    expect(
      c.profile.artists[first.artist],
      signalWeights[Signal.complete]! + signalWeights[Signal.replay]!,
    );
  });

  test('dislike removes upcoming songs by that artist and advances', () async {
    await build(['A', 'B', 'A', 'C', 'A']);
    await c.init();
    await settle();
    final requests = <int>[];
    final sub = c.advanceRequests.listen(requests.add);
    final first = c.items[0];
    final before = c.items.map((i) => i.track.artist).toList();
    c.dislike(first);
    await settle();
    final expected = [
      first.track.artist,
      ...before.skip(1).where((a) => a != first.track.artist),
    ];
    expect(c.items.map((i) => i.track.artist), expected);
    expect(c.profile.blockedArtists, {first.track.artist});
    expect(requests, [1]);
    // 离开时不再重复记一次跳过。
    await c.onPageChanged(1);
    expect(c.profile.artists[first.track.artist], signalWeights[Signal.dislike]);
    await sub.cancel();
  });

  test('like persists across controller instances', () async {
    await build(['A']);
    await c.init();
    await settle();
    final t = c.items.first.track;
    expect(await c.toggleLike(t), isTrue);
    expect(c.isLiked(t), isTrue);
    final reopened = c.store.loadLiked();
    expect(reopened, [t]);
    expect(await c.toggleLike(t), isFalse);
    expect(c.store.loadLiked(), isEmpty);
  });

  test('double-tap like never un-likes', () async {
    await build(['A']);
    await c.init();
    await settle();
    final t = c.items.first.track;
    await c.like(t);
    await c.like(t);
    expect(c.isLiked(t), isTrue);
    expect(c.profile.artists[t.artist], signalWeights[Signal.like]);
  });

  test('a broken track is marked failed instead of crashing', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    audio.failIds.add(c.items[1].track.id);
    await c.onPageChanged(1);
    expect(c.items[1].failed, isTrue);
  });

  test('swiping past the end waits, then plays when the batch arrives', () async {
    audio = FakeAudio();
    final source = SequenceSource([
      [track('a', artist: 'A')],
      [track('b', artist: 'B')],
    ]);
    c = FeedController(
      recommender: Recommender(source: source, profile: TasteProfile(), seeds: ['s']),
      audio: audio,
      store: await memoryStore(),
      prefetchThreshold: 0,
    );
    await c.init();
    await settle();
    expect(audio.played, ['a']);

    source.gate = Completer<void>();
    await c.onPageChanged(1); // 划到了还没加载出来的「加载中」页。
    expect(audio.isPlaying, isFalse);
    expect(c.current, isNull);

    source.gate!.complete();
    await settle();
    await settle();
    expect(c.items.map((i) => i.track.id), ['a', 'b']);
    expect(audio.played, ['a', 'b']);
    expect(c.index, 1);
  });

  test('notes are stored per track', () async {
    await build(['A']);
    await c.init();
    await settle();
    final t = c.items.first.track;
    await c.addNote(t, '  好听  ');
    await c.addNote(t, '   ');
    expect(c.notesFor(t), ['好听']);
    expect(c.store.loadNotes()[t.id], ['好听']);
  });

  test('insertNext puts a liked song right after the current one', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final at = c.insertNext(track('liked', artist: 'Z'));
    expect(at, 1);
    expect(c.items[1].reason, '来自我喜欢');
  });

  test('network failure surfaces an error and retry recovers', () async {
    audio = FakeAudio();
    final source = SequenceSource([[track('ok')]])..gate = Completer<void>();
    c = FeedController(
      recommender: Recommender(source: FailingSource(), profile: TasteProfile(), seeds: ['s']),
      audio: FakeAudio(),
      store: await memoryStore(),
    );
    await c.init();
    expect(c.error, 'offline');
    expect(c.items, isEmpty);

    final recovered = FeedController(
      recommender: Recommender(source: source, profile: TasteProfile(), seeds: ['s']),
      audio: audio,
      store: await memoryStore(),
    );
    final init = recovered.init();
    expect(recovered.loading, isTrue);
    source.gate!.complete();
    await init;
    await settle();
    expect(recovered.error, isNull);
    expect(audio.played, ['ok']);
  });

  test('retry on the same controller recovers and starts playing', () async {
    audio = FakeAudio();
    c = FeedController(
      recommender: Recommender(
        source: FlakySource(3, [track('ok')]),
        profile: TasteProfile(),
        seeds: ['s'],
      ),
      audio: audio,
      store: await memoryStore(),
    );
    await c.init();
    expect(c.error, 'offline');
    expect(audio.played, isEmpty);

    await c.retry();
    await settle();
    expect(c.error, isNull);
    expect(audio.played, ['ok']);
  });
}
