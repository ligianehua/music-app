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

  test('completion plays the next song by itself, without the UI', () async {
    // 锁屏时界面不绘制、不翻页，只有控制器自己切歌才能连播。
    await build(['A', 'B']);
    await c.init();
    await settle();
    final first = c.items[0].track;
    final second = c.items[1].track;
    audio.complete();
    // 切歌瞬间旧播放器补发的「放完」：不应把新歌当成放完而连跳两首。
    audio.completeStale(first.id);
    await settle();
    expect(audio.played, [first.id, second.id]);
    expect(c.index, 1);
    expect(c.profile.artists[first.artist], signalWeights[Signal.complete]);
    // 界面随后翻到同一页时不应重复触发。
    await c.onPageChanged(1);
    expect(audio.played, [first.id, second.id]);
  });

  test('no auto advance when disabled', () async {
    await build(['A', 'B'], autoAdvance: false);
    await c.init();
    await settle();
    audio.complete();
    await settle();
    expect(audio.played, hasLength(1));
    expect(c.index, 0);
  });

  test('completing the last song waits for the next batch, then keeps playing', () async {
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
    source.gate = Completer<void>();
    audio.complete();
    await settle();
    expect(c.index, 1);
    expect(c.current, isNull);
    source.gate!.complete();
    await settle();
    await settle();
    expect(audio.played, ['a', 'b']);
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
    // 直接切到下一首，离开时也不再重复记一次跳过。
    expect(c.index, 1);
    expect(audio.played.last, c.items[1].track.id);
    expect(c.profile.artists[first.track.artist], signalWeights[Signal.dislike]);
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

  group('lock screen and notification', () {
    late FakeSession session;

    Future<void> buildWithSession(List<String> artists) async {
      audio = FakeAudio();
      session = FakeSession();
      var n = 0;
      c = FeedController(
        recommender: Recommender(
          source: FakeSource({}, fallback: [
            for (final a in artists) track('t${n++}', artist: a),
          ]),
          profile: TasteProfile(),
          seeds: ['seed'],
          maxPerArtist: 99,
        ),
        audio: audio,
        store: await memoryStore(),
        session: session,
        prefetchThreshold: 0,
      );
      await c.init();
      await settle();
    }

    test('attaches itself and publishes the current song', () async {
      await buildWithSession(['A', 'B']);
      expect(session.commands, same(c));
      expect(session.last.track, c.items[0].track);
      expect(session.last.playing, isTrue);
      expect(session.last.duration, const Duration(seconds: 30));
      expect(session.last.hasPrevious, isFalse);
    });

    test('lock screen next / previous move through the feed', () async {
      await buildWithSession(['A', 'B', 'C']);
      final first = c.items[0].track;
      audio.tick(const Duration(seconds: 2));
      await session.commands!.next();
      expect(c.index, 1);
      expect(session.last.track, c.items[1].track);
      expect(session.last.hasPrevious, isTrue);
      // 锁屏点「下一首」和手势秒划是同一个信号。
      expect(c.profile.artists[first.artist], signalWeights[Signal.quickSkip]);

      await session.commands!.previous();
      expect(c.index, 0);
      expect(session.last.track, first);
      await session.commands!.previous(); // 第一首再按上一首：无事发生。
      expect(c.index, 0);
    });

    test('lock screen pause / play / seek', () async {
      await buildWithSession(['A']);
      await session.commands!.pause();
      expect(audio.isPlaying, isFalse);
      expect(session.last.playing, isFalse);
      await session.commands!.play();
      expect(session.last.playing, isTrue);
      await session.commands!.seek(const Duration(seconds: 12));
      expect(session.last.position, const Duration(seconds: 12));
    });

    test('notification heart toggles like on the current song', () async {
      await buildWithSession(['A']);
      final t = c.items[0].track;
      await session.commands!.toggleLikeCurrent();
      expect(c.isLiked(t), isTrue);
      expect(session.last.liked, isTrue);
      await session.commands!.toggleLikeCurrent();
      expect(c.isLiked(t), isFalse);
      expect(session.last.liked, isFalse);
    });

    test('songs keep playing back to back while locked', () async {
      await buildWithSession(['A', 'B', 'C']);
      audio.complete();
      await settle();
      audio.complete();
      await settle();
      expect(audio.played, [for (final i in c.items) i.track.id]);
      expect(session.last.track, c.items[2].track);
    });
  });
}
