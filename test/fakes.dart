import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/audio/audio_engine.dart';
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

/// 记录调用、可手动推进的假播放器。
class FakeAudio implements AudioEngine {
  final position$ = StreamController<Duration>.broadcast(sync: true);
  final duration$ = StreamController<Duration?>.broadcast(sync: true);
  final playing$ = StreamController<bool>.broadcast(sync: true);
  final completed$ = StreamController<void>.broadcast(sync: true);
  final List<String> played = [];
  final List<String> preloaded = [];
  final Set<String> failIds = {};
  bool isPlaying = false;

  @override
  Stream<Duration> get positionStream => position$.stream;
  @override
  Stream<Duration?> get durationStream => duration$.stream;
  @override
  Stream<bool> get playingStream => playing$.stream;
  @override
  Stream<void> get completedStream => completed$.stream;
  @override
  Duration position = Duration.zero;

  void tick(Duration p) {
    position = p;
    position$.add(p);
  }

  void complete() => completed$.add(null);

  @override
  Future<void> preload(Track track) async => preloaded.add(track.id);

  @override
  Future<void> play(Track track) async {
    if (failIds.contains(track.id)) throw Exception('bad url');
    played.add(track.id);
    duration$.add(const Duration(seconds: 30));
    isPlaying = true;
    playing$.add(true);
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
