import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/feed/feed_controller.dart';
import 'package:shuage/recommend/recommender.dart';
import 'package:shuage/lyrics/offset_store.dart';
import 'package:shuage/recommend/taste_profile.dart';
import 'package:shuage/social/comment.dart';

import 'fakes.dart';

/// 让排队的微任务和异步回调都跑完。
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudio audio;
  late FeedController c;

  Future<FeedController> build(List<String> artists) async {
    audio = FakeAudio();
    var n = 0;
    final source = FakeSource({}, fallback: [
      for (final a in artists) track('t${n++}', artist: a),
    ]);
    c = FeedController(
      user: testUser,
      recommender: Recommender(
        source: source,
        profile: TasteProfile(),
        seeds: ['seed'],
        maxPerArtist: 99,
        exploreRatio: 1,
      ),
      audio: audio,
      store: await memoryStore(),
      prefetchThreshold: 0,
    );
    return c;
  }

  test('init loads a batch into the native queue and plays the first', () async {
    await build(['A', 'B', 'C']);
    await c.init();
    await settle();
    expect(c.items, hasLength(3));
    // 整批都进了原生队列，播完由原生层自己接下一首。
    expect(audio.queueIds, [for (final i in c.items) i.track.id]);
    expect(audio.played, [c.items[0].track.id]);
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

  test('native auto-advance moves the feed along, without the UI', () async {
    // 锁屏时界面不绘制、不翻页：原生队列自己接下一首，控制器跟上。
    await build(['A', 'B']);
    await c.init();
    await settle();
    final first = c.items[0].track;
    final second = c.items[1].track;
    audio.finish();
    await settle();
    expect(audio.played, [first.id, second.id]);
    expect(c.index, 1);
    expect(c.profile.artists[first.artist], signalWeights[Signal.complete]);
    // 界面随后翻到同一页时不应重复跳转或计分。
    await c.onPageChanged(1);
    expect(audio.played, [first.id, second.id]);
    expect(c.profile.artists[first.artist], signalWeights[Signal.complete]);
  });

  test('an echo of our own jump is not treated as auto-advance', () async {
    await build(['A', 'B', 'C']);
    await c.init();
    await settle();
    await c.goTo(2);
    audio.advance$.add(2); // 原生层迟到的回声
    await settle();
    expect(c.index, 2);
    expect(audio.played, [c.items[0].track.id, c.items[2].track.id]);
  });

  test('a native load error is skipped without scoring the broken song', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final broken = c.items[0].track;
    audio.failAndSkip(0);
    await settle();
    expect(c.items[0].failed, isTrue);
    expect(c.index, 1);
    expect(c.profile.artists[broken.artist], isNull);
  });

  test('completing the last song waits for the next batch, then keeps playing', () async {
    audio = FakeAudio();
    final source = SequenceSource([
      [track('a', artist: 'A')],
      [track('b', artist: 'B')],
    ]);
    c = FeedController(
      user: testUser,
      recommender: Recommender(source: source, profile: TasteProfile(), seeds: ['s']),
      audio: audio,
      store: await memoryStore(),
      prefetchThreshold: 0,
    );
    await c.init();
    await settle();
    source.gate = Completer<void>();
    audio.finish(); // 原生队列播完了最后一首
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
    // 原生队列同步删除，两边一一对应。
    expect(audio.queueIds, [for (final i in c.items) i.track.id]);
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
      user: testUser,
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

  group('comments, favorites and search', () {
    late SharedPreferences prefs;

    Future<void> buildSocial() async {
      audio = FakeAudio();
      final store = await memoryStore();
      prefs = await SharedPreferences.getInstance();
      c = FeedController(
        user: testUser,
        recommender: Recommender(
          source: FakeSource({}, fallback: [track('t1', artist: 'A'), track('t2', artist: 'B')]),
          profile: TasteProfile(),
          seeds: ['s'],
        ),
        audio: audio,
        store: store,
        comments: LocalCommentStore(prefs),
        prefetchThreshold: 0,
      );
      await c.init();
      await settle();
    }

    test('comments are signed by the member and counted', () async {
      await buildSocial();
      final t = c.items.first.track;
      expect(c.commentCount(t), 0, reason: '切到这首时已经加载过评论');
      final posted = await c.addComment(t, '  好听  ');
      expect(posted.text, '好听');
      expect(posted.username, testUser.username);
      expect(c.commentCount(t), 1);
      await c.deleteComment(posted);
      expect(c.commentCount(t), 0);
    });

    test('favorite is separate from like and a stronger signal', () async {
      await buildSocial();
      final t = c.items.first.track;
      expect(await c.toggleFavorite(t), isTrue);
      expect(c.isFavorite(t), isTrue);
      expect(c.isLiked(t), isFalse);
      expect(c.store.loadFavorites(), [t]);
      expect(c.profile.artists[t.artist], signalWeights[Signal.favorite]);
      expect(await c.toggleFavorite(t), isFalse);
      expect(c.store.loadFavorites(), isEmpty);
      expect(c.profile.artists[t.artist], isNull);
    });

    test('search is remembered and steers the profile', () async {
      await buildSocial();
      await c.recordSearch('  陈奕迅 ');
      await c.recordSearch('周杰伦');
      await c.recordSearch('陈奕迅');
      expect(c.searchHistory, ['陈奕迅', '周杰伦']);
      expect(c.profile.searches.keys, containsAll(['陈奕迅', '周杰伦']));
      expect(c.profile.searches['陈奕迅']! > c.profile.searches['周杰伦']!, isTrue);
      await c.clearSearchHistory();
      expect(c.searchHistory, isEmpty);
    });

    test('playNow from search plays immediately, then the feed continues', () async {
      await buildSocial();
      final picked = track('found', artist: 'Z');
      await c.playNow(picked, reason: 'From your search');
      expect(c.current!.track, picked);
      expect(c.current!.reason, 'From your search');
      expect(audio.played.last, 'found');
      expect(audio.queueIds, [for (final i in c.items) i.track.id]);
      // 已在播的歌再点一次不会重复插入。
      final before = c.items.length;
      await c.playNow(picked, reason: 'From your search');
      expect(c.items.length, before);
    });
  });

  test('insertNext puts a liked song right after the current one', () async {
    await build(['A', 'B']);
    await c.init();
    await settle();
    final at = c.insertNext(track('liked', artist: 'Z'));
    expect(at, 1);
    expect(c.items[1].reason, 'From your saved songs');
    expect(audio.queueIds, [for (final i in c.items) i.track.id]);
    // 原生层播完当前这首，接的就是插进来的这首。
    audio.finish();
    await settle();
    expect(c.current!.track.id, 'liked');
  });

  test('network failure surfaces an error and retry recovers', () async {
    audio = FakeAudio();
    final source = SequenceSource([[track('ok')]])..gate = Completer<void>();
    c = FeedController(
      user: testUser,
      recommender: Recommender(source: FailingSource(), profile: TasteProfile(), seeds: ['s']),
      audio: FakeAudio(),
      store: await memoryStore(),
    );
    await c.init();
    expect(c.error, 'offline');
    expect(c.items, isEmpty);

    final recovered = FeedController(
      user: testUser,
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
      user: testUser,
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
        user: testUser,
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
      audio.finish();
      await settle();
      audio.finish();
      await settle();
      expect(audio.played, [for (final i in c.items) i.track.id]);
      expect(session.last.track, c.items[2].track);
    });
  });

  test('a new batch arriving after the queue ran dry keeps playing', () async {
    audio = FakeAudio();
    final source = SequenceSource([
      [track('a', artist: 'A'), track('b', artist: 'B')],
      [track('c', artist: 'C')],
    ]);
    c = FeedController(
      user: testUser,
      recommender: Recommender(source: source, profile: TasteProfile(), seeds: ['s']),
      audio: audio,
      store: await memoryStore(),
      prefetchThreshold: 0,
    );
    await c.init();
    await settle();
    source.gate = Completer<void>();
    audio.finish();
    audio.finish(); // b 也播完，队列空了
    await settle();
    source.gate!.complete();
    await settle();
    await settle();
    // 头两首的顺序由推荐打分决定，不固定；第三首是新到的那批。
    expect(audio.played, hasLength(3));
    expect(audio.played.last, 'c');
    expect(audio.queueIds, audio.played);
  });

  test('prefetched batches are appended while the current song plays', () async {
    audio = FakeAudio();
    final source = SequenceSource([
      [track('a', artist: 'A'), track('b', artist: 'B')],
      [track('c', artist: 'C'), track('d', artist: 'D')],
    ]);
    c = FeedController(
      user: testUser,
      recommender: Recommender(source: source, profile: TasteProfile(), seeds: ['s']),
      audio: audio,
      store: await memoryStore(),
      prefetchThreshold: 3,
    );
    await c.init();
    for (var i = 0; i < 4; i++) {
      await settle();
    }
    // 一开始就不足三首，下一批已经进了原生队列，原生层可以一路播下去。
    expect(audio.queueIds.toSet(), {'a', 'b', 'c', 'd'});
    for (var i = 0; i < 3; i++) {
      audio.finish();
      await settle();
    }
    expect(audio.played, hasLength(4));
  });

  test('an empty catalog shows a message instead of spinning forever', () async {
    c = FeedController(
      user: testUser,
      recommender: Recommender(
          source: FakeSource({}), profile: TasteProfile(), seeds: ['s']),
      audio: FakeAudio(),
      store: await memoryStore(),
    );
    await c.init();
    expect(c.loading, isFalse);
    expect(c.items, isEmpty);
    expect(c.error, contains('No playable songs'));
  });

  test('unexpected errors also surface instead of spinning forever', () async {
    final source = FakeSource({})..throwOnce = StateError('boom');
    c = FeedController(
      user: testUser,
      recommender: Recommender(source: source, profile: TasteProfile(), seeds: ['s']),
      audio: FakeAudio(),
      store: await memoryStore(),
    );
    await c.init();
    expect(c.loading, isFalse);
    expect(c.error, contains('boom'));
  });

  test('lyrics calibration is remembered per song', () async {
    audio = FakeAudio();
    final store = await memoryStore();
    final prefs = await SharedPreferences.getInstance();
    c = FeedController(
      user: testUser,
      recommender: Recommender(
          source: FakeSource({}, fallback: [track('a')]),
          profile: TasteProfile(),
          seeds: ['s']),
      audio: audio,
      store: store,
      lyricsOffsets: LyricsOffsetStore(prefs),
    );
    final t = track('a');
    expect(c.lyricsOffsetFor(t), isNull);
    var notified = 0;
    c.addListener(() => notified++);
    await c.calibrateLyrics(t, const Duration(seconds: 61));
    expect(c.lyricsOffsetFor(t), const Duration(seconds: 61));
    expect(notified, 1);
    // 换一个控制器（比如重新登录）也还在。
    expect(LyricsOffsetStore(prefs).get('a'), const Duration(seconds: 61));
  });
}
