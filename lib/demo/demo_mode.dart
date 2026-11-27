import 'dart:async';
import 'dart:math';

import '../audio/audio_engine.dart';
import '../data/lyrics_source.dart';
import '../data/track_source.dart';
import '../lyrics/lrc.dart';
import '../models/track.dart';

/// 离线演示模式，只用于在没有网络时预览界面和交互：
///
///     flutter run --dart-define=SHUAGE_DEMO=true
///
/// 歌曲是明确标注的占位数据，没有真实音频，播放进度由计时器模拟。
const bool kDemoMode = bool.fromEnvironment('SHUAGE_DEMO');

class DemoSource implements TrackSource {
  int _n = 0;
  static const _artists = ['演示歌手 A', '演示歌手 B', '演示歌手 C', '演示歌手 D'];
  static const _genres = ['流行', '民谣', '电子', 'R&B'];

  @override
  Future<List<Track>> search(String term, {int limit = 30}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.generate(limit, (_) {
      final i = _n++;
      return Track(
        id: 'demo:$i',
        title: '示例歌曲 ${i + 1}',
        artist: _artists[i % _artists.length],
        album: '演示专辑',
        artworkUrl: '',
        previewUrl: '',
        genre: _genres[i % _genres.length],
      );
    });
  }
}

class DemoLyricsSource implements LyricsSource {
  @override
  Future<Lyrics?> fetch(Track track) async => Lyrics(plain: [
        for (var i = 1; i <= 4; i++) '（演示歌词）主歌第 $i 行',
        for (var r = 0; r < 2; r++) ...[
          '（演示歌词）这是副歌',
          '（演示歌词）副歌会重复',
        ],
      ]);
}

/// 用计时器模拟一个原生播放队列，每首 30 秒，播完自动接下一首。
class DemoAudioEngine implements AudioEngine {
  static const length = Duration(seconds: 30);
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _autoAdvance = StreamController<int>.broadcast();
  final _queueEnd = StreamController<void>.broadcast();
  final _errors = StreamController<int>.broadcast();
  final List<Track> _queue = [];
  int _current = -1;
  Timer? _timer;
  Duration _pos = Duration.zero;

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<int> get autoAdvanceStream => _autoAdvance.stream;
  @override
  Stream<void> get queueEndStream => _queueEnd.stream;
  @override
  Stream<int> get errorStream => _errors.stream;
  @override
  Duration get position => _pos;

  @override
  Future<void> append(List<Track> tracks) async => _queue.addAll(tracks);

  @override
  Future<void> insert(int index, Track track) async {
    _queue.insert(index, track);
    if (index <= _current) _current++;
  }

  @override
  Future<void> removeAt(int index) async {
    _queue.removeAt(index);
    if (index < _current) _current--;
  }

  @override
  Future<void> playAt(int index) async {
    _current = index;
    _pos = Duration.zero;
    _duration.add(length);
    await resume();
  }

  @override
  Future<void> resume() async {
    _timer?.cancel();
    if (_pos >= length) _pos = Duration.zero;
    _playing.add(true);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _tick() {
    _pos = Duration(
        milliseconds: min(_pos.inMilliseconds + 200, length.inMilliseconds));
    _position.add(_pos);
    if (_pos < length) return;
    if (_current + 1 < _queue.length) {
      _current++;
      _pos = Duration.zero;
      _duration.add(length);
      _autoAdvance.add(_current);
    } else {
      _timer?.cancel();
      _playing.add(false);
      _queueEnd.add(null);
    }
  }

  @override
  Future<void> pause() async {
    _timer?.cancel();
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    _pos = position;
    _position.add(_pos);
  }

  @override
  Future<void> dispose() async => _timer?.cancel();
}
