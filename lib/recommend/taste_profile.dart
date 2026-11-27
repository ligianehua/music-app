import '../models/track.dart';

/// 用户对一首歌的反馈。刷歌的核心是：**行为就是标签**，用户不需要手动打分。
enum Signal {
  /// 前 20% 就划走：强烈不喜欢。
  quickSkip,

  /// 听了不到一半就走：轻微不喜欢。
  earlySkip,

  /// 听了一半以上才走：轻微喜欢。
  lateSkip,

  /// 完整听完试听片段。
  complete,

  /// 划回去又听了一遍。
  replay,

  /// 红心。
  like,

  /// 取消红心，抵消一次 [like]。
  unlike,

  /// 点了「不感兴趣」：同歌手之后不再推荐。
  dislike,
}

/// 每种信号对歌手的加减分。风格按一半计算。
const Map<Signal, double> signalWeights = {
  Signal.quickSkip: -1.0,
  Signal.earlySkip: -0.3,
  Signal.lateSkip: 0.3,
  Signal.complete: 1.0,
  Signal.replay: 1.5,
  Signal.like: 2.0,
  Signal.unlike: -2.0,
  Signal.dislike: -3.0,
};

/// 按收听比例把一次「划走」翻译成信号。
Signal signalForListen(Duration listened, Duration total) {
  if (total <= Duration.zero) return Signal.earlySkip;
  final ratio = listened.inMilliseconds / total.inMilliseconds;
  if (ratio >= 0.9) return Signal.complete;
  if (ratio >= 0.5) return Signal.lateSkip;
  if (ratio >= 0.2) return Signal.earlySkip;
  return Signal.quickSkip;
}

/// 本地口味画像：歌手和风格两个维度的累计分。
class TasteProfile {
  TasteProfile({
    Map<String, double>? artists,
    Map<String, double>? genres,
    Set<String>? blockedArtists,
  })  : artists = artists ?? {},
        genres = genres ?? {},
        blockedArtists = blockedArtists ?? {};

  static const double maxScore = 10;

  final Map<String, double> artists;
  final Map<String, double> genres;
  final Set<String> blockedArtists;

  void record(Track track, Signal signal) {
    final w = signalWeights[signal]!;
    _bump(artists, track.artist, w);
    if (track.genre.isNotEmpty) _bump(genres, track.genre, w / 2);
    if (signal == Signal.dislike) blockedArtists.add(track.artist);
  }

  void _bump(Map<String, double> m, String key, double delta) {
    final v = ((m[key] ?? 0) + delta).clamp(-maxScore, maxScore).toDouble();
    if (v == 0) {
      m.remove(key);
    } else {
      m[key] = v;
    }
  }

  bool isBlocked(Track t) => blockedArtists.contains(t.artist);

  /// 越高越可能被推荐。被拉黑的歌手返回负无穷。
  double score(Track t) {
    if (isBlocked(t)) return double.negativeInfinity;
    return (artists[t.artist] ?? 0) + (genres[t.genre] ?? 0) * 0.5;
  }

  /// 正分最高的若干项，用来生成下一批搜索词。
  List<MapEntry<String, double>> topPositive(Map<String, double> m, int n) {
    final list = m.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  bool get hasPreference =>
      artists.values.any((v) => v > 0) || genres.values.any((v) => v > 0);

  Map<String, dynamic> toJson() => {
        'artists': artists,
        'genres': genres,
        'blocked': blockedArtists.toList(),
      };

  factory TasteProfile.fromJson(Map<String, dynamic> json) {
    Map<String, double> toMap(Object? v) => v is Map
        ? v.map((k, val) => MapEntry('$k', (val as num).toDouble()))
        : {};
    return TasteProfile(
      artists: toMap(json['artists']),
      genres: toMap(json['genres']),
      blockedArtists: {
        ...((json['blocked'] as List?) ?? const []).map((e) => '$e'),
      },
    );
  }
}
