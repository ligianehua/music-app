import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'audio_engine.dart';

/// 基于 just_audio 原生播放队列的实现。
///
/// 只有一个 [AudioPlayer]，刷歌流里的歌都在它的队列里。好处：
/// - 播完自动接下一首由原生层完成，不依赖 Dart 代码，锁屏连播更稳；
/// - 下一首由原生层提前缓冲，歌与歌之间无缝；
/// - 某首加载失败时原生层自动跳过（最多连续 [maxSkipsOnError] 首）。
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({AudioPlayer? player, this.maxSkipsOnError = 3})
      : _player = player ?? AudioPlayer(maxSkipsOnError: maxSkipsOnError) {
    _subs
      ..add(_player.currentIndexStream.listen((i) {
        if (i == null) return;
        final advanced = _detector.onIndex(i);
        if (advanced != null) _autoAdvance.add(advanced);
      }))
      ..add(_player.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) _queueEnd.add(null);
      }))
      ..add(_player.errorStream.listen((e) {
        final i = e.index ?? _player.currentIndex;
        if (i != null) _errors.add(i);
      }));
  }

  final AudioPlayer _player;
  final int maxSkipsOnError;
  final _detector = AdvanceDetector();
  final List<StreamSubscription<dynamic>> _subs = [];
  final _autoAdvance = StreamController<int>.broadcast();
  final _queueEnd = StreamController<void>.broadcast();
  final _errors = StreamController<int>.broadcast();
  bool _hasQueue = false;

  /// 队列操作必须按顺序执行，否则序号会错位。
  Future<void> _ops = Future.value();

  Future<void> _serial(Future<void> Function() op) {
    final next = _ops.then((_) => op());
    _ops = next.catchError((Object _) {});
    return next;
  }

  /// 有高潮起播点的整首歌用裁剪片段，原生自动接到它时也从高潮开始。
  static AudioSource sourceFor(Track t) {
    final uri = AudioSource.uri(Uri.parse(t.previewUrl), tag: t.id);
    if (t.highlightStartMs <= 0) return uri;
    return ClippingAudioSource(
      child: uri,
      start: Duration(milliseconds: t.highlightStartMs),
      tag: t.id,
    );
  }

  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Stream<int> get autoAdvanceStream => _autoAdvance.stream;
  @override
  Stream<void> get queueEndStream => _queueEnd.stream;
  @override
  Stream<int> get errorStream => _errors.stream;
  @override
  Duration get position => _player.position;

  @override
  Future<void> append(List<Track> tracks) => _serial(() async {
        if (tracks.isEmpty) return;
        final sources = tracks.map(sourceFor).toList();
        if (_hasQueue) {
          await _player.addAudioSources(sources);
        } else {
          _hasQueue = true;
          await _player.setAudioSources(sources, preload: false);
        }
      });

  @override
  Future<void> insert(int index, Track track) =>
      _serial(() => _player.insertAudioSource(index, sourceFor(track)));

  @override
  Future<void> removeAt(int index) =>
      _serial(() => _player.removeAudioSourceAt(index));

  @override
  Future<void> playAt(int index) => _serial(() async {
        _detector.expect(index);
        try {
          await _player.seek(Duration.zero, index: index);
        } catch (_) {
          _detector.cancel();
          rethrow;
        }
        // play() 要到暂停或播完才返回，不能 await。
        unawaited(_player.play());
      });

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: _player.currentIndex);
    }
    unawaited(_player.play());
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _autoAdvance.close();
    await _queueEnd.close();
    await _errors.close();
  }
}
