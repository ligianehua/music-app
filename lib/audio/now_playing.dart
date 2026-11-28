import '../models/track.dart';

/// 系统层面「正在播放」的一帧快照：锁屏、通知栏、耳机线控、车机看到的都是它。
class NowPlaying {
  const NowPlaying({
    required this.track,
    required this.liked,
    required this.playing,
    required this.position,
    this.duration,
    this.hasPrevious = false,
  });

  final Track track;
  final bool liked;
  final bool playing;
  final Duration position;
  final Duration? duration;

  /// 是否能回到上一首。第一首时锁屏不显示「上一首」。
  final bool hasPrevious;
}

/// 锁屏、通知栏、耳机按键发来的指令。由刷歌流控制器实现。
abstract class RemoteCommands {
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> toggleLikeCurrent();
}

/// 系统媒体会话。控制器只依赖这个接口，测试时换成假实现。
abstract class NowPlayingSession {
  /// 绑定指令接收方。
  void attach(RemoteCommands commands);

  /// 推送最新状态。
  void update(NowPlaying state);
}
