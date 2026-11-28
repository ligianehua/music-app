import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuage/audio/now_playing.dart';
import 'package:shuage/audio/system_media_session.dart';

import 'fakes.dart';

class RecordingCommands implements RemoteCommands {
  final List<String> calls = [];
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> seek(Duration p) async => calls.add('seek ${p.inSeconds}');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> toggleLikeCurrent() async => calls.add('like');
}

NowPlaying state({bool liked = false, bool playing = true, bool hasPrevious = true}) =>
    NowPlaying(
      track: track('1', artist: '歌手'),
      liked: liked,
      playing: playing,
      position: const Duration(seconds: 3),
      duration: const Duration(seconds: 30),
      hasPrevious: hasPrevious,
    );

void main() {
  group('playbackStateFor', () {
    test('full notification: heart, previous, play/pause, next', () {
      final s = playbackStateFor(state());
      expect(s.controls.map((c) => c.action), [
        MediaAction.custom,
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.skipToNext,
      ]);
      expect(s.controls.first.label, 'Like');
      // 收起时：红心、播放/暂停、下一首。
      expect(s.androidCompactActionIndices, [0, 2, 3]);
      expect(s.playing, isTrue);
      expect(s.updatePosition, const Duration(seconds: 3));
      expect(s.systemActions, contains(MediaAction.seek));
      expect(s.systemActions, contains(MediaAction.skipToPrevious));
    });

    test('liked + paused swaps the icons', () {
      final s = playbackStateFor(state(liked: true, playing: false));
      expect(s.controls.first.label, 'Unlike');
      expect(s.controls[2].action, MediaAction.play);
    });

    test('no previous on the first song', () {
      final s = playbackStateFor(state(hasPrevious: false));
      expect(s.systemActions, isNot(contains(MediaAction.skipToPrevious)));
      expect(s.controls.map((c) => c.action),
          isNot(contains(MediaAction.skipToPrevious)));
      expect(s.androidCompactActionIndices, [0, 1, 2]);
    });
  });

  test('mediaItemFor maps song info and heart rating', () {
    final m = mediaItemFor(state(liked: true));
    expect(m.title, 'Song 1');
    expect(m.artist, '歌手');
    expect(m.duration, const Duration(seconds: 30));
    expect(m.artUri, isNull);
    expect(m.rating?.hasHeart(), isTrue);
  });

  group('ShuageAudioHandler', () {
    late ShuageAudioHandler handler;
    late RecordingCommands commands;

    setUp(() {
      handler = ShuageAudioHandler();
      commands = RecordingCommands();
      SystemMediaSession(handler).attach(commands);
    });

    test('forwards system commands', () async {
      await handler.play();
      await handler.pause();
      await handler.seek(const Duration(seconds: 9));
      await handler.skipToNext();
      await handler.skipToPrevious();
      await handler.customAction(likeActionName);
      await handler.customAction('unknown');
      expect(commands.calls,
          ['play', 'pause', 'seek 9', 'next', 'previous', 'like']);
    });

    test('setRating only toggles when the heart actually changes', () async {
      final session = SystemMediaSession(handler)..attach(commands);
      session.update(state(liked: true));
      await handler.setRating(const Rating.newHeartRating(true));
      expect(commands.calls, isEmpty);
      await handler.setRating(const Rating.newHeartRating(false));
      expect(commands.calls, ['like']);
    });

    test('session re-sends song info only when it changes', () {
      final session = SystemMediaSession(handler);
      final items = <MediaItem?>[];
      final sub = handler.mediaItem.listen(items.add);
      session.update(state());
      session.update(state(playing: false)); // 只是暂停：不重发歌曲信息
      session.update(state(liked: true)); // 红心变化：重发
      return Future<void>.delayed(Duration.zero, () {
        // 第一个是 BehaviorSubject 的初始 null。
        expect(items.whereType<MediaItem>(), hasLength(2));
        expect(handler.playbackState.value.playing, isTrue);
        sub.cancel();
      });
    });
  });
}
