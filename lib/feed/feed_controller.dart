import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_engine.dart';
import '../audio/now_playing.dart';
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

  /// 播放失败（地址失效等）时为 true。
  bool failed = false;
}

/// 刷歌流的状态和行为。
///
/// 规则：
/// - 滑到哪张就播哪张，离开时按「听了多久」给口味画像打分；
/// - 剩余不足 [prefetchThreshold] 张时自动拉下一批；
/// - 当前这首放完由原生播放队列自动接下一首；
/// - 划回已经听过的歌记为 [Signal.replay]。
///
/// [items] 和播放引擎的原生队列一一对应，所有增删都同步到引擎。
/// 导航以控制器为准，界面只跟随 [index]，所以锁屏时界面不绘制也能连播。
class FeedController extends ChangeNotifier implements RemoteCommands {
  FeedController({
    required this.recommender,
    required this.audio,
    required this.store,
    this.lyricsSource,
    this.session,
    this.prefetchThreshold = 3,
    this.previewLength = const Duration(seconds: 30),
  }) {
    _subs
      ..add(audio.positionStream.listen(_onPosition))
      ..add(audio.durationStream.listen((d) {
        duration.value = d;
        _publish();
      }))
      ..add(audio.playingStream.listen((p) {
        playing.value = p;
        _publish();
      }))
      ..add(audio.autoAdvanceStream.listen(_onAutoAdvance))
      ..add(audio.queueEndStream.listen((_) => _onQueueEnd()))
      ..add(audio.errorStream.listen(_onError));
    session?.attach(this);
  }

  final Recommender recommender;
  final AudioEngine audio;
  final LibraryStore store;
  final LyricsSource? lyricsSource;

  /// 锁屏和通知栏。为 null 时不对接系统媒体会话。
  final NowPlayingSession? session;
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

  final List<StreamSubscription<dynamic>> _subs = [];
  final Set<String> _played = {};
  List<Track> _liked = [];
  Map<String, List<String>> _notes = {};
  Duration _maxListened = Duration.zero;

  /// 当前这首已经记过「听完」或「不感兴趣」，离开时不再重复计分。
  bool _scoredCurrent = false;
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
    var added = 0;
    try {
      final recs = await recommender.nextBatch();
      added = recs.length;
      items.addAll(recs.map((r) => FeedItem(r.track, r.reason)));
      error = null;
      // 先进原生队列再开播：队列里有了，原生层才能自己接上去。
      unawaited(_guard(audio.append([for (final r in recs) r.track])));
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
    // 加载期间触发的补货请求会被 loading 挡掉，所以到货后再查一次：
    // 还不够就接着补，直到够了或拉不到新歌为止。
    if (added > 0 && items.length - index <= prefetchThreshold) {
      unawaited(_loadMore());
    }
  }

  /// PageView 翻页回调：用户手动划到了第 [newIndex] 张。
  Future<void> onPageChanged(int newIndex) => goTo(newIndex);

  /// 主动切到第 [newIndex] 张。手势、锁屏按钮、不感兴趣都走这里。
  Future<void> goTo(int newIndex) async {
    if (newIndex < 0) return;
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

  /// 进入第 [i] 张。[fromEngine] 为 true 表示原生队列已经在播它了，不用再跳。
  Future<void> _activate(int i, {bool fromEngine = false}) async {
    if (i < 0 || i >= items.length) return;
    _pendingIndex = null;
    index = i;
    final item = items[i];
    if (_played.contains(item.track.id)) _record(item.track, Signal.replay);
    _played.add(item.track.id);
    _maxListened = Duration.zero;
    _scoredCurrent = false;
    position.value = Duration.zero;
    duration.value = null;
    _notify();
    _publish();

    if (items.length - i <= prefetchThreshold) unawaited(_loadMore());
    if (fromEngine) return;
    try {
      await audio.playAt(i);
    } catch (_) {
      item.failed = true;
      _notify();
    }
  }

  void _onPosition(Duration p) {
    position.value = p;
    if (p > _maxListened) _maxListened = p;
  }

  /// 原生队列自己接到了第 [i] 首：上一首是完整听完的。
  void _onAutoAdvance(int i) {
    if (i == index || i >= items.length) return;
    final previous = current;
    if (previous != null && !previous.failed && !_scoredCurrent) {
      _record(previous.track, Signal.complete);
    }
    _scoredCurrent = true;
    unawaited(_activate(i, fromEngine: true));
  }

  /// 队列最后一首也播完了：记一次听完，进入「等下一批」，到了自动接着播。
  void _onQueueEnd() {
    final item = current;
    if (item == null || _scoredCurrent) return;
    if (!item.failed) _record(item.track, Signal.complete);
    _scoredCurrent = true;
    unawaited(goTo(index + 1));
  }

  /// 第 [i] 首加载失败。原生层会自动跳过；连续失败太多时会停下，卡片上提示。
  void _onError(int i) {
    if (i < 0 || i >= items.length) return;
    items[i].failed = true;
    _notify();
  }

  /// 离开当前歌：放完的已经记过了，没放完的按听了多久打分。
  void _recordLeave() {
    final item = current;
    if (item == null || _scoredCurrent || item.failed) return;
    final total = duration.value ?? previewLength;
    _record(item.track, signalForListen(_maxListened, total));
  }

  void _record(Track t, Signal s) {
    profile.record(t, s);
    unawaited(store.saveProfile(profile));
  }

  Future<void> togglePlay() => playing.value ? pause() : play();

  @override
  Future<void> play() async {
    if (current == null) return;
    await audio.resume();
  }

  @override
  Future<void> pause() => audio.pause();

  @override
  Future<void> next() => goTo(index + 1);

  @override
  Future<void> previous() => goTo(index - 1);

  @override
  Future<void> toggleLikeCurrent() async {
    final item = current;
    if (item != null) await toggleLike(item.track);
  }

  @override
  Future<void> seek(Duration to) async {
    if (to > _maxListened) _maxListened = to;
    await audio.seek(to);
    _publish();
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
    _publish();
    await store.saveLiked(_liked);
    return nowLiked;
  }

  /// 只点亮红心，不会取消。给「双击」用：双击永远是加红心。
  Future<void> like(Track t) async {
    if (!isLiked(t)) await toggleLike(t);
  }

  /// 不感兴趣：拉黑歌手，移除后面同歌手的歌，并切到下一首。
  void dislike(FeedItem item) {
    _record(item.track, Signal.dislike);
    final at = items.indexOf(item);
    if (at == index) _scoredCurrent = true;
    // 从后往前删，原生队列同步删同一位置，序号才不会错位。
    for (var j = items.length - 1; j > at; j--) {
      if (items[j].track.artist == item.track.artist) {
        items.removeAt(j);
        unawaited(_guard(audio.removeAt(j)));
      }
    }
    _notify();
    if (items.length - at <= prefetchThreshold) unawaited(_loadMore());
    if (at == index) unawaited(goTo(at + 1));
  }

  Future<void> addNote(Track t, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    (_notes[t.id] ??= []).add(trimmed);
    _notify();
    await store.saveNotes(_notes);
  }

  /// 从「我喜欢」里点一首：插到当前位置后面，返回插入的位置。
  int insertNext(Track t) {
    recommender.markSeen(t);
    final at = (index + 1).clamp(0, items.length);
    items.insert(at, FeedItem(t, '来自我喜欢'));
    unawaited(_guard(audio.insert(at, t)));
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

  /// 队列同步失败只记日志，不让异常冒泡成未捕获错误。
  Future<void> _guard(Future<void> op) => op.catchError((Object e) {
        debugPrint('播放队列同步失败：$e');
      });

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 把当前状态推给锁屏和通知栏。
  void _publish() {
    final item = current;
    if (_disposed || session == null || item == null) return;
    session!.update(NowPlaying(
      track: item.track,
      liked: isLiked(item.track),
      playing: playing.value,
      position: audio.position,
      duration: duration.value,
      hasPrevious: index > 0,
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    position.dispose();
    duration.dispose();
    playing.dispose();
    super.dispose();
  }
}
