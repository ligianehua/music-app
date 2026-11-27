/// 一行带时间戳的歌词。
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => '[$time] $text';
}

/// 一首歌的歌词。[synced] 有值时可以逐行高亮。
class Lyrics {
  const Lyrics({this.synced, this.plain = const []});
  final List<LyricLine>? synced;
  final List<String> plain;

  bool get isEmpty => (synced?.isEmpty ?? true) && plain.isEmpty;

  /// 不管有没有时间轴，都能拿到纯文本行。
  List<String> get lines => synced?.map((l) => l.text).toList() ?? plain;
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// 解析 LRC 文本。支持一行多个时间戳，忽略 `[ar:xxx]` 这类元信息和空行。
List<LyricLine> parseLrc(String source) {
  final out = <LyricLine>[];
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final tags = _timeTag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    final text = raw.substring(tags.last.end).trim();
    if (text.isEmpty) continue;
    for (final m in tags) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final frac = m.group(3);
      // ".5" 是 500 毫秒，".05" 是 50 毫秒，".005" 是 5 毫秒。
      final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0'));
      out.add(LyricLine(
        Duration(minutes: min, seconds: sec, milliseconds: ms),
        text,
      ));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// 返回 [position] 时刻应该高亮的行号；还没到第一行时返回 -1。
int lyricIndexAt(List<LyricLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= position) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
