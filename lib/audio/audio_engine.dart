import 'dart:async';

import '../models/track.dart';

/// 播放引擎接口。控制器只依赖它，测试时可以换成假实现。
abstract class AudioEngine {
  /// 当前歌的播放位置。
  Stream<Duration> get positionStream;

  /// 当前歌的时长；未知时为 null。
  Stream<Duration?> get durationStream;

  Stream<bool> get playingStream;

  /// 某首歌放完时触发，带上这首歌的 id。
  ///
  /// 带 id 是为了防串台：切歌瞬间旧播放器可能补发一次「放完」，
  /// 控制器据此忽略，不会把新歌当成放完而连跳两首。
  Stream<String> get completedStream;

  Duration get position;

  /// 提前缓冲，滑过去时零等待。
  Future<void> preload(Track track);

  /// 切到这首歌并从高潮段开始播。
  Future<void> play(Track track);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> dispose();
}
