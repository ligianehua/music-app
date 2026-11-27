import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'audio_engine.dart';

/// 基于 just_audio 的实现。
///
/// 每首歌一个 [AudioPlayer]，最多同时保留 [poolSize] 个：当前、下一首、
/// 和刚刚划走的那首（方便下滑回看时不用重新缓冲）。
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({this.poolSize = 3});

  final int poolSize;
  final Map<String, AudioPlayer> _players = {};
  final Map<String, Future<void>> _loading = {};
  final List<String> _lru = [];
  String? _activeId;
  final List<StreamSubscription<dynamic>> _subs = [];

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _completed.stream;

  AudioPlayer? get _active => _activeId == null ? null : _players[_activeId];

  @override
  Duration get position => _active?.position ?? Duration.zero;

  Future<AudioPlayer> _ensure(Track track) async {
    var player = _players[track.id];
    if (player == null) {
      player = AudioPlayer();
      _players[track.id] = player;
      _loading[track.id] = player
          .setUrl(track.previewUrl,
              initialPosition: Duration(milliseconds: track.highlightStartMs))
          .then((_) {});
    }
    _touch(track.id);
    _evict();
    await _loading[track.id];
    return player;
  }

  void _touch(String id) {
    _lru
      ..remove(id)
      ..add(id);
  }

  void _evict() {
    while (_lru.length > poolSize) {
      final victim = _lru.firstWhere((id) => id != _activeId);
      _lru.remove(victim);
      _loading.remove(victim);
      _players.remove(victim)?.dispose();
    }
  }

  @override
  Future<void> preload(Track track) async {
    try {
      await _ensure(track);
    } catch (_) {
      // 预加载失败不影响当前播放；真正滑到时会再报错。
    }
  }

  @override
  Future<void> play(Track track) async {
    final previous = _active;
    _activeId = track.id;
    await previous?.pause();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();

    final player = await _ensure(track);
    if (_activeId != track.id) return; // 加载期间用户又划走了。

    _subs
      ..add(player.positionStream.listen(_position.add))
      ..add(player.durationStream.listen(_duration.add))
      ..add(player.playingStream.listen(_playing.add))
      ..add(player.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) _completed.add(null);
      }));
    await player.seek(Duration(milliseconds: track.highlightStartMs));
    // play() 的 Future 要到暂停或播完才结束，这里不能 await。
    unawaited(player.play());
  }

  @override
  Future<void> pause() async => _active?.pause();

  @override
  Future<void> resume() async {
    final p = _active;
    if (p == null) return;
    if (p.processingState == ProcessingState.completed) {
      await p.seek(Duration.zero);
    }
    unawaited(p.play());
  }

  @override
  Future<void> seek(Duration position) async => _active?.seek(position);

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
  }
}
