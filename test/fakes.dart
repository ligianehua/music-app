import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/audio/audio_engine.dart';
import 'package:shuage/audio/now_playing.dart';
import 'package:shuage/data/library_store.dart';
import 'package:shuage/data/track_source.dart';
import 'package:shuage/models/track.dart';

Track track(String id, {String artist = 'A', String genre = 'Pop'}) => Track(
      id: id,
      title: 'Song $id',
      artist: artist,
      album: 'Album',
      artworkUrl: '',
      previewUrl: 'https://example.com/$id.m4a',
      genre: genre,
    );

/// 按搜索词返回预设结果，并记录被搜了哪些词。
class FakeSource implements TrackSource {
  FakeSource(this.byTerm, {this.fallback = const []});
  final Map<String, List<Track>> byTerm;
  final List<Track> fallback;
  final List<String> terms = [];
  Object? throwOnce;

  @override
  Future<List<Track>> search(String term, {int limit = 30}) async {
    terms.add(term);
    final e = throwOnce;
    if (e != null) {
      throwOnce = null;
      throw e;
    }
    return byTerm[term] ?? fallback;
  }
}

/// 总是失败的音源。
class FailingSource implements TrackSource {
  @override
  Future<List<Track>> search(String term, {int limit = 30}) async =>
      throw TrackSourceException('offline');
}

/// 模拟原生播放队列的假播放器，可手动让当前这首「播完」。
class FakeAudio implements AudioEngine {
  final position$ = StreamController<Duration>.broadcast(sync: true);
  final duration$ = StreamController<Duration?>.broadcast(sync: true);
  final playing$ = StreamController<bool>.broadcast(sync: true);
  final advance$ = StreamController<int>.broadcast(sync: true);
  final queueEnd$ = StreamController<void>.broadcast(sync: true);
  final error$ = StreamController<int>.broadcast(sync: true);

  /// 原生队列内容。
  final List<Track> queue = [];
  int current = -1;

  /// 实际开始播放过的歌，按顺序。
  final List<String> played = [];
  final Set<String> failIds = {};
  bool isPlaying = false;

  List<String> get queueIds => [for (final t in queue) t.id];

  @override
  Stream<Duration> get positionStream => position$.stream;
  @override
  Stream<Duration?> get durationStream => duration$.stream;
  @override
  Stream<bool> get playingStream => playing$.stream;
  @override
  Stream<int> get autoAdvanceStream => advance$.stream;
  @override
  Stream<void> get queueEndStream => queueEnd$.stream;
  @override
  Stream<int> get errorStream => error$.stream;
  @override
  Duration position = Duration.zero;

  void tick(Duration p) {
    position = p;
    position$.add(p);
  }

  void _start(int i) {
    current = i;
    played.add(queue[i].id);
    position = Duration.zero;
    duration$.add(const Duration(seconds: 30));
    isPlaying = true;
    playing$.add(true);
  }

  /// 当前这首播完：原生层自己接下一首，或者报告队列播完。
  void finish() {
    if (current + 1 < queue.length) {
      _start(current + 1);
      advance$.add(current);
    } else {
      isPlaying = false;
      playing$.add(false);
      queueEnd$.add(null);
    }
  }

  /// 原生层报告第 [i] 首加载失败，并像 maxSkipsOnError 那样自动跳过。
  void failAndSkip(int i) {
    error$.add(i);
    finish();
  }

  @override
  Future<void> append(List<Track> tracks) async => queue.addAll(tracks);

  @override
  Future<void> insert(int index, Track track) async {
    queue.insert(index, track);
    if (index <= current) current++;
  }

  @override
  Future<void> removeAt(int index) async {
    queue.removeAt(index);
    if (index < current) current--;
  }

  @override
  Future<void> playAt(int index) async {
    if (failIds.contains(queue[index].id)) throw Exception('bad url');
    _start(index);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    playing$.add(false);
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
    playing$.add(true);
  }

  @override
  Future<void> seek(Duration p) async => tick(p);

  @override
  Future<void> dispose() async {}
}

Future<LibraryStore> memoryStore([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return LibraryStore(await SharedPreferences.getInstance());
}

/// 每次搜索依次返回下一批；设置 [gate] 后会等它完成才返回。
class SequenceSource implements TrackSource {
  SequenceSource(this.batches);
  final List<List<Track>> batches;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<List<Track>> search(String term, {int limit = 30}) async {
    final g = gate;
    if (g != null) await g.future;
    final i = calls++;
    return i < batches.length ? batches[i] : const [];
  }
}

/// 前 [failures] 次搜索失败，之后返回 [tracks]。
class FlakySource implements TrackSource {
  FlakySource(this.failures, this.tracks);
  int failures;
  final List<Track> tracks;

  @override
  Future<List<Track>> search(String term, {int limit = 30}) async {
    if (failures > 0) {
      failures--;
      throw TrackSourceException('offline');
    }
    return tracks;
  }
}

/// 记录推送内容的假系统会话，可以模拟锁屏按键。
class FakeSession implements NowPlayingSession {
  RemoteCommands? commands;
  final List<NowPlaying> updates = [];

  NowPlaying get last => updates.last;

  @override
  void attach(RemoteCommands c) => commands = c;

  @override
  void update(NowPlaying state) => updates.add(state);
}
