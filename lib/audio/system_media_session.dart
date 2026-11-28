import 'package:audio_service/audio_service.dart';

import 'now_playing.dart';

/// 通知栏「喜欢」按钮的自定义指令名。
const likeActionName = 'like';

/// 安卓通知栏的红心按钮。图标在 android/app/src/main/res/drawable。
/// iOS 锁屏不支持自定义按钮，红心只出现在安卓。
final likeControl = MediaControl.custom(
  androidIcon: 'drawable/ic_shuage_like',
  label: 'Like',
  name: likeActionName,
);

final likedControl = MediaControl.custom(
  androidIcon: 'drawable/ic_shuage_liked',
  label: 'Unlike',
  name: likeActionName,
);

/// 把 [NowPlaying] 翻译成系统通知需要的歌曲信息。
MediaItem mediaItemFor(NowPlaying s) {
  final t = s.track;
  return MediaItem(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album.isEmpty ? null : t.album,
    genre: t.genre.isEmpty ? null : t.genre,
    duration: s.duration,
    artUri: t.artworkUrl.isEmpty ? null : Uri.parse(t.artworkUrl),
    rating: Rating.newHeartRating(s.liked),
  );
}

/// 把 [NowPlaying] 翻译成播放状态和按钮。
///
/// 展开的通知栏：红心、上一首（有的话）、播放/暂停、下一首。
/// 收起时只留三个：红心、播放/暂停、下一首。
/// 「上一首」必须放进按钮列表：网页版只按按钮列表注册系统按键。
PlaybackState playbackStateFor(NowPlaying s) {
  final controls = [
    s.liked ? likedControl : likeControl,
    if (s.hasPrevious) MediaControl.skipToPrevious,
    s.playing ? MediaControl.pause : MediaControl.play,
    MediaControl.skipToNext,
  ];
  final playPause = controls.length - 2;
  return PlaybackState(
    controls: controls,
    systemActions: {
      MediaAction.seek,
      MediaAction.playPause,
      MediaAction.skipToNext,
      if (s.hasPrevious) MediaAction.skipToPrevious,
    },
    androidCompactActionIndices: [0, playPause, playPause + 1],
    processingState: AudioProcessingState.ready,
    playing: s.playing,
    updatePosition: s.position,
    speed: 1.0,
  );
}

/// 接收系统指令并转给 [RemoteCommands] 的处理器。
class ShuageAudioHandler extends BaseAudioHandler {
  RemoteCommands? commands;

  @override
  Future<void> play() async => commands?.play();

  @override
  Future<void> pause() async => commands?.pause();

  @override
  Future<void> seek(Duration position) async => commands?.seek(position);

  @override
  Future<void> skipToNext() async => commands?.next();

  @override
  Future<void> skipToPrevious() async => commands?.previous();

  /// 部分车机和手表通过「评分」来点红心，传来的是目标状态。
  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) async {
    final liked = mediaItem.value?.rating?.hasHeart() ?? false;
    if (rating.hasHeart() != liked) await commands?.toggleLikeCurrent();
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == likeActionName) await commands?.toggleLikeCurrent();
  }

  /// 用户从多任务里划掉 App：停播并收起通知。
  @override
  Future<void> onTaskRemoved() async {
    await commands?.pause();
    await stop();
  }
}

/// 基于 audio_service 的系统媒体会话：锁屏控制、安卓通知栏播放器、耳机线控。
class SystemMediaSession implements NowPlayingSession {
  SystemMediaSession(this.handler);

  final ShuageAudioHandler handler;
  NowPlaying? _last;

  static Future<SystemMediaSession> init() async {
    final handler = await AudioService.init(
      builder: ShuageAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.shuage.shuage.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationChannelDescription: 'Playback controls on the lock screen and in notifications',
        // 播放时通知不能被划掉；暂停后可以划掉，系统也可回收服务。
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    return SystemMediaSession(handler);
  }

  @override
  void attach(RemoteCommands commands) => handler.commands = commands;

  @override
  void update(NowPlaying state) {
    final last = _last;
    _last = state;
    // 只在歌曲信息变化时重发，避免锁屏封面反复闪烁重载。
    final itemChanged = last == null ||
        last.track != state.track ||
        last.liked != state.liked ||
        last.duration != state.duration;
    if (itemChanged) handler.mediaItem.add(mediaItemFor(state));
    handler.playbackState.add(playbackStateFor(state));
  }
}
