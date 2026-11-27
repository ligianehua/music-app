import 'dart:async';

import '../models/track.dart';

/// 播放引擎接口：一个原生播放队列。
///
/// 队列和刷歌流的列表一一对应，由控制器负责同步增删。播完一首后由原生播放器
/// 自己接下一首（iOS 的 AVQueuePlayer、安卓的 ExoPlayer），不经过 Dart 代码，
/// 锁屏、熄屏时也能无缝连播。
abstract class AudioEngine {
  /// 当前这首的播放位置。
  Stream<Duration> get positionStream;

  /// 当前这首的时长；未知时为 null。
  Stream<Duration?> get durationStream;

  Stream<bool> get playingStream;

  /// 原生播放器**自己**换到了队列第几首：播完接下一首，或跳过了加载失败的条目。
  /// 由 [playAt] 主动跳转引起的变化不会发出。
  Stream<int> get autoAdvanceStream;

  /// 队列里最后一首也播完了。
  Stream<void> get queueEndStream;

  /// 队列第几首加载或播放失败。
  Stream<int> get errorStream;

  Duration get position;

  /// 往队尾追加。
  Future<void> append(List<Track> tracks);

  /// 在第 [index] 位插入。
  Future<void> insert(int index, Track track);

  /// 移除第 [index] 位。
  Future<void> removeAt(int index);

  /// 跳到第 [index] 首，从高潮段开始播。
  Future<void> playAt(int index);

  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

/// 区分「原生播放器自己换歌」和「我们主动跳转之后的回声」。
///
/// 原生播放器每次换歌都会报告当前序号，但不说是谁触发的。如果把主动跳转的回声
/// 也当成自动换歌，快速连划时迟到的旧序号会把刷歌流拽回去。规则：
/// - 发起跳转时登记目标；目标到达之前的所有序号都是过程或回声，一律不上报；
/// - 没有登记目标时，序号变化才是原生自己换的歌。
class AdvanceDetector {
  int? _current;
  int? _target;

  /// 即将主动跳到 [target]。
  void expect(int target) {
    if (target != _current) _target = target;
  }

  /// 跳转失败，不会再有回声。
  void cancel() => _target = null;

  /// 收到原生报告的序号。返回需要上报的自动换歌位置，否则返回 null。
  int? onIndex(int index) {
    final previous = _current;
    _current = index;
    if (_target != null) {
      if (index == _target) _target = null;
      return null;
    }
    if (previous == null || index == previous) return null;
    return index;
  }
}
