import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_engine.dart';
import '../data/library_store.dart';
import '../data/lyrics_source.dart';
import '../data/track_source.dart';
import '../lyrics/lrc.dart';
import '../models/track.dart';
import '../recommend/recommender.dart';
import '../recommend/taste_profile.dart';

/// 流里的一张卡片。
class FeedItem {
  FeedItem(this.track, this.reason);
  final Track track;
  final String reason;

  /// 播放失败（地址失效等）时为 true，界面提示用户划走。
  bool failed = false;
}

/// 刷歌流的状态和行为。
///
/// 规则：
/// - 滑到哪张就播哪张，离开时按「听了多久」给口味画像打分；
/// - 剩余不足 [prefetchThreshold] 张时自动拉下一批；
/// - 当前这首放完自动续到下一张（[autoAdvance]）；
/// - 划回已经听过的歌记为 [Signal.replay]。
class FeedController extends ChangeNotifier {
  FeedController({
    required this.recommender,
    required this.audio,
    required this.store,
    this.lyricsSource,
    this.autoAdvance = true,
    this.prefetchThreshold = 3,
    this.previewLength = const Duration(seconds: 30),
  }) {
    _subs
      ..add(audio.positionStream.listen(_onPosition))
      ..add(audio.durationStream.listen((d) => duration.value = d))
      ..add(audio.playingStream.listen((p) => playing.value = p))
      ..add(audio.completedStream.listen((_) => _onCompleted()));
  }

  final Recommender recommender;
  final AudioEngine audio;
  final LibraryStore store;
  final LyricsSource? lyricsSource;
  final bool autoAdvance;
  final int prefetchThreshold;

  /// 时长未知时用来计算收听比例。
  final Duration previewLength;

  TasteProfile get profile => recommender.profile;

  final List<FeedItem> items = [];
  int index = 0;
  bool loading = false;
  String? error;

  /// 高频变化的播放状态单独用 ValueNotifier，避免整页重建。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> duration = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);

  final _advance = StreamController<int>.broadcast();

  /// 控制器希望界面翻到的页码（自动续播、点了不感兴趣）。
  Stream<int> get advanceRequests => _advance.stream;

  final List<StreamSubscription<dynamic>> _subs = [];
  final Set<String> _played = {};
  List<Track> _liked = [];
  Map<String, List<String>> _notes = {};
  Duration _maxListened = Duration.zero;
  bool _completedCurrent = false;
  bool _disposed = false;

  /// 用户划到了还没加载出来的位置，加载完成后从这里开始播。
  int? _pendingIndex;

  FeedItem? get current =>
      index >= 0 && index < items.length ? items[index] : null;

  List<Track> get liked => List.unmodifiable(_liked);

  bool isLiked(Track t) => _liked.contains(t);

  List<String> notesFor(Track t) => List.unmodifiable(_notes[t.id] ?? const []);

  Future<void> init() async {
    _liked = store.loadLiked();
    _notes = store.loadNotes();
    _pendingIndex = 0;
    await _loadMore();
  }

  /// 网络失败后重试。
  Future<void> retry() async {
    error = null;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (loading) return;
    loading = true;
    _notify();
    try {
      final recs = await recommender.nextBatch();
      items.addAll(recs.map((r) => FeedItem(r.track, r.reason)));
      error = null;
      final pending = _pendingIndex;
      if (pending != null && pending < items.length) {
        unawaited(_activate(pending));
      }
    } on TrackSourceException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      _notify();
    }
  }

  /// PageView 翻页回调。
  Future<void> onPageChanged(int newIndex) async {
    if (newIndex == index && _played.contains(current?.track.id)) return;
    _recordLeave();
    if (newIndex >= items.length) {
      // 刷得比加载快：先停播，等这一批到了再接着放。
      index = newIndex;
      _pendingIndex = newIndex;
      await audio.pause();
      _notify();
      unawaited(_loadMore());
      return;
    }
    await _activate(newIndex);
  }

  Future<void> _activate(int i) async {
    if (i < 0 || i >= items.length) return;
    _pendingIndex = null;
    index = i;
    final item = items[i];
    final isReplay = _played.contains(item.track.id);
    if (isReplay) _record(item.track, Signal.replay);
    _played.add(item.track.id);
    _maxListened = Duration.zero;
    _completedCurrent = false;
    position.value = Duration.zero;
    duration.value = null;
    _notify();

    if (items.length - i <= prefetchThreshold) unawaited(_loadMore());
    if (i + 1 < items.length) unawaited(audio.preload(items[i + 1].track));

    try {
      await audio.play(item.track);
    } catch (_) {
      item.failed = true;
      _notify();
    }
  }

  void _onPosition(Duration p) {
    position.value = p;
    if (p > _maxListened) _maxListened = p;
  }

  void _onCompleted() {
    final item = current;
    if (item == null || _completedCurrent) return;
    _completedCurrent = true;
    _record(item.track, Signal.complete);
    if (autoAdvance && index + 1 < items.length) _advance.add(index + 1);
  }

  /// 离开当前歌：放完的已经记过了，没放完的按听了多久打分。
  void _recordLeave() {
    final item = current;
    if (item == null || _completedCurrent || item.failed) return;
    final total = duration.value ?? previewLength;
    _record(item.track, signalForListen(_maxListened, total));
  }

  void _record(Track t, Signal s) {
    profile.record(t, s);
    unawaited(store.saveProfile(profile));
  }

  Future<void> togglePlay() async {
    if (playing.value) {
      await audio.pause();
    } else {
      await audio.resume();
    }
  }

  Future<void> seek(Duration to) async {
    if (to > _maxListened) _maxListened = to;
    await audio.seek(to);
  }

  /// 切换红心。返回切换后是否为红心状态。
  Future<bool> toggleLike(Track t) async {
    final nowLiked = !isLiked(t);
    if (nowLiked) {
      _liked.insert(0, t);
      _record(t, Signal.like);
    } else {
      _liked.remove(t);
      _record(t, Signal.unlike);
    }
    _notify();
    await store.saveLiked(_liked);
    return nowLiked;
  }

  /// 只点亮红心，不会取消。给「双击」用：双击永远是加红心。
  Future<void> like(Track t) async {
    if (!isLiked(t)) await toggleLike(t);
  }

  /// 不感兴趣：拉黑歌手，移除后面同歌手的歌，并请求翻到下一张。
  void dislike(FeedItem item) {
    _record(item.track, Signal.dislike);
    _completedCurrent = true; // 已经记过强负反馈，离开时不再重复记分。
    final at = items.indexOf(item);
    final rest = items
        .sublist(at + 1)
        .where((other) => other.track.artist != item.track.artist)
        .toList();
    items
      ..removeRange(at + 1, items.length)
      ..addAll(rest);
    _notify();
    if (items.length - at <= prefetchThreshold) unawaited(_loadMore());
    if (at + 1 < items.length) _advance.add(at + 1);
  }

  Future<void> addNote(Track t, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    (_notes[t.id] ??= []).add(trimmed);
    _notify();
    await store.saveNotes(_notes);
  }

  /// 从「我喜欢」里点一首：插到当前位置后面并请求跳过去。
  int insertNext(Track t) {
    recommender.markSeen(t);
    final at = (index + 1).clamp(0, items.length);
    items.insert(at, FeedItem(t, '来自我喜欢'));
    _notify();
    return at;
  }

  Future<Lyrics?> lyricsFor(Track t) =>
      lyricsSource?.fetch(t) ?? Future.value(null);

  /// 清空口味画像，下一批重新冷启动。
  Future<void> resetTaste() async {
    profile.artists.clear();
    profile.genres.clear();
    profile.blockedArtists.clear();
    await store.resetProfile();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _advance.close();
    position.dispose();
    duration.dispose();
    playing.dispose();
    super.dispose();
  }
}
