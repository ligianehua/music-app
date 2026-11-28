import 'chorus.dart';
import 'lrc.dart';

/// 估算试听片段的第 0 秒对应原曲的哪个时刻。
///
/// 苹果的试听起点由发行方设定，接口不提供，只能估：
/// 1. 有反复出现的歌词行：假定试听从副歌第一次出现处开始；
/// 2. 否则取原曲 30% 处附近的那一行（试听很少从开头截）；
/// 3. 连时长都不知道：从第一行开始。
///
/// 估不准时，用户点一下正在唱的那一行即可校准。
Duration estimatePreviewOffset(List<LyricLine> lines, {int trackDurationMs = 0}) {
  if (lines.isEmpty) return Duration.zero;
  final chorus = repeatedLineIndex([for (final l in lines) l.text]);
  if (chorus != null) return lines[chorus].time;
  if (trackDurationMs > 0) {
    final guess = Duration(milliseconds: (trackDurationMs * 0.3).round());
    final i = lyricIndexAt(lines, guess);
    return lines[i < 0 ? 0 : i].time;
  }
  return lines.first.time;
}

/// 用户点了第 [line] 行、此刻试听播放到 [position]：算出新的偏移，
/// 让这一行正好对准当前位置。
Duration offsetForTap(LyricLine line, Duration position) => line.time - position;
