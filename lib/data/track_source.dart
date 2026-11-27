import '../models/track.dart';

/// 歌曲来源。推荐器只依赖这个接口，换曲库时只需要换实现。
abstract class TrackSource {
  /// 按关键词（歌手名、风格名等）搜歌，只返回能播放的结果。
  Future<List<Track>> search(String term, {int limit = 30});
}

class TrackSourceException implements Exception {
  TrackSourceException(this.message);
  final String message;

  @override
  String toString() => message;
}
