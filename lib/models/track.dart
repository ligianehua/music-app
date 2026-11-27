/// 一首可以被「刷」到的歌。
///
/// 当前音源是 iTunes 30 秒试听片段，所以 [previewUrl] 本身就接近高潮段。
/// 接入完整音源后，用 [highlightStartMs] 指定从哪一毫秒开始播放。
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    required this.previewUrl,
    this.genre = '',
    this.durationMs = 0,
    this.storeUrl,
    this.highlightStartMs = 0,
  });

  final String id;
  final String title;
  final String artist;
  final String album;

  /// 封面图。为空时界面会按 [id] 生成渐变占位。
  final String artworkUrl;

  /// 可直接播放的音频地址。
  final String previewUrl;
  final String genre;

  /// 整首歌的时长（毫秒），用来查歌词。
  final int durationMs;

  /// 应用商店或详情页链接，分享时使用。
  final String? storeUrl;

  /// 起播位置。对试听片段来说就是 0。
  final int highlightStartMs;

  /// 把 iTunes Search API 的一条结果转成 [Track]。
  ///
  /// iTunes 只给 100x100 的封面，这里按其 URL 约定换成 600x600。
  factory Track.fromItunes(Map<String, dynamic> json) {
    final art = (json['artworkUrl100'] as String? ?? '')
        .replaceAll('100x100bb', '600x600bb');
    return Track(
      id: 'itunes:${json['trackId']}',
      title: (json['trackName'] as String?) ?? '未知歌曲',
      artist: (json['artistName'] as String?) ?? '未知歌手',
      album: (json['collectionName'] as String?) ?? '',
      artworkUrl: art,
      previewUrl: (json['previewUrl'] as String?) ?? '',
      genre: (json['primaryGenreName'] as String?) ?? '',
      durationMs: (json['trackTimeMillis'] as num?)?.toInt() ?? 0,
      storeUrl: json['trackViewUrl'] as String?,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String? ?? '',
        previewUrl: json['previewUrl'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        storeUrl: json['storeUrl'] as String?,
        highlightStartMs: (json['highlightStartMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'previewUrl': previewUrl,
        'genre': genre,
        'durationMs': durationMs,
        'storeUrl': storeUrl,
        'highlightStartMs': highlightStartMs,
      };

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($title - $artist)';
}
