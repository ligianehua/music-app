import 'dart:math';

import '../data/track_source.dart';
import '../models/track.dart';
import 'taste_profile.dart';

/// 推荐结果，附带一句「为什么推给你」。透明的理由能让用户信任推荐，
/// 也让探索内容不显得突兀。
class Recommendation {
  const Recommendation(this.track, this.reason);
  final Track track;
  final String reason;
}

/// 冷启动和探索用的种子词。
const defaultSeeds = <String>[
  '周杰伦', '林俊杰', '陈奕迅', '邓紫棋', '五月天', '孙燕姿', '王菲',
  '毛不易', '李荣浩', '薛之谦', '告五人', '陶喆', '蔡依林', '方大同',
  'Taylor Swift', 'The Weeknd', 'Billie Eilish', 'Coldplay', 'Bruno Mars',
  'NewJeans', 'IU', '米津玄師', 'YOASOBI',
  '华语流行', 'city pop', 'lofi', 'R&B', '民谣', '摇滚', '电子',
];

/// 「80% 投其所好 + 20% 探索」的推荐器。
///
/// 只用口味画像会越推越窄（过滤气泡），所以固定留一部分流量给探索。
class Recommender {
  Recommender({
    required this.source,
    required this.profile,
    Random? random,
    this.exploreRatio = 0.2,
    this.maxPerArtist = 2,
    List<String>? seeds,
  })  : _random = random ?? Random(),
        seeds = seeds ?? defaultSeeds;

  final TrackSource source;
  final TasteProfile profile;
  final double exploreRatio;

  /// 一批里同一歌手最多出现几首，避免连刷同一个人。
  final int maxPerArtist;
  final List<String> seeds;
  final Random _random;
  final Set<String> _seen = {};

  /// 每次搜 30 首只用一小部分，剩下的留作备用。
  /// 网络出错或拉回空结果时直接从这里出歌，刷歌流不会断粮。
  final List<Recommendation> _reserve = [];

  /// 备用池上限，超出时丢掉最早的。
  static const maxReserve = 60;

  int get reserveSize => _reserve.length;

  /// 已经推过的歌不再推。外部插入的歌也要登记，避免重复。
  void markSeen(Track t) => _seen.add(t.id);

  /// 拉下一批推荐。
  ///
  /// - 某个搜索词没结果：换词重试，最多 [maxAttempts] 次；
  /// - 网络出错：有备用歌就立刻用备用，没有才重试；
  /// - 都不行：用备用歌兜底，备用也空了才报错。
  Future<List<Recommendation>> nextBatch({
    int size = 8,
    int maxAttempts = 3,
  }) async {
    TrackSourceException? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      // 第一次失败后强制走探索，换一个完全不同的词。
      final pick = _pickTerm(forceExplore: attempt > 0);
      List<Track> found;
      try {
        found = await source.search(pick.term, limit: 30);
      } on TrackSourceException catch (e) {
        lastError = e;
        // 网络问题换词也没用，别让用户干等重试。
        if (_reserve.isNotEmpty) break;
        continue;
      }
      final batch = _rank(found, size);
      if (batch.isNotEmpty) {
        for (final t in batch) {
          _seen.add(t.id);
        }
        _stash(found, pick.reason);
        return [for (final t in batch) Recommendation(t, pick.reason)];
      }
    }
    final fallback = _takeFromReserve(size);
    if (fallback.isNotEmpty) return fallback;
    if (lastError != null) throw lastError;
    return const [];
  }

  /// 把这次没用上的歌存进备用池。
  void _stash(List<Track> found, String reason) {
    final known = {for (final r in _reserve) r.track.id};
    for (final t in found) {
      if (_seen.contains(t.id) || known.contains(t.id)) continue;
      known.add(t.id);
      _reserve.add(Recommendation(t, reason));
    }
    if (_reserve.length > maxReserve) {
      _reserve.removeRange(0, _reserve.length - maxReserve);
    }
  }

  /// 从备用池按当前口味挑一批。口味可能已经变了，所以用的时候才排序。
  List<Recommendation> _takeFromReserve(int size) {
    _reserve.removeWhere(
        (r) => _seen.contains(r.track.id) || profile.isBlocked(r.track));
    final reasons = {for (final r in _reserve) r.track.id: r.reason};
    final batch = _rank([for (final r in _reserve) r.track], size);
    final ids = {for (final t in batch) t.id};
    _reserve.removeWhere((r) => ids.contains(r.track.id));
    for (final t in batch) {
      _seen.add(t.id);
    }
    return [for (final t in batch) Recommendation(t, reasons[t.id]!)];
  }

  List<Track> _rank(List<Track> found, int size) {
    final fresh = found
        .where((t) => !_seen.contains(t.id) && !profile.isBlocked(t))
        .toList();
    // 画像分 + 随机扰动：既尊重偏好，又不至于每次顺序一样。
    final keyed = {
      for (final t in fresh) t: profile.score(t) + _random.nextDouble() * 1.5,
    };
    fresh.sort((a, b) => keyed[b]!.compareTo(keyed[a]!));
    final perArtist = <String, int>{};
    final out = <Track>[];
    final ids = <String>{};
    for (final t in fresh) {
      if (ids.contains(t.id)) continue;
      final n = perArtist[t.artist] ?? 0;
      if (n >= maxPerArtist) continue;
      perArtist[t.artist] = n + 1;
      ids.add(t.id);
      out.add(t);
      if (out.length >= size) break;
    }
    return out;
  }

  ({String term, String reason}) _pickTerm({bool forceExplore = false}) {
    final explore = forceExplore ||
        !profile.hasPreference ||
        _random.nextDouble() < exploreRatio;
    if (!explore) {
      final artists = profile.topPositive(profile.artists, 5);
      final genres = profile.topPositive(profile.genres, 3);
      final pool = [
        for (final e in artists) (term: e.key, w: e.value, kind: 'artist'),
        for (final e in genres) (term: e.key, w: e.value * 0.6, kind: 'genre'),
      ];
      if (pool.isNotEmpty) {
        final total = pool.fold<double>(0, (s, e) => s + e.w);
        var r = _random.nextDouble() * total;
        for (final e in pool) {
          r -= e.w;
          if (r <= 0) {
            return (
              term: e.term,
              reason: e.kind == 'artist' ? '因为你常听 ${e.term}' : '你最近爱听 ${e.term}',
            );
          }
        }
        final last = pool.last;
        return (term: last.term, reason: '因为你常听 ${last.term}');
      }
    }
    final candidates =
        seeds.where((s) => !profile.blockedArtists.contains(s)).toList();
    final term = candidates[_random.nextInt(candidates.length)];
    return (
      term: term,
      reason: profile.hasPreference ? '换换口味：$term' : '热门推荐：$term',
    );
  }
}
