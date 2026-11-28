/// 估算副歌从第几行开始：重复次数最多的那一行第一次出现的位置。
///
/// 试听片段通常截在副歌附近，但不知道精确偏移，所以无法逐行同步。
/// 退而求其次：把歌词面板直接滚到副歌，用户看到的大概率就是正在唱的段落。
int chorusStartIndex(List<String> lines) => repeatedLineIndex(lines) ?? 0;

/// 重复次数最多的那一行第一次出现的位置；没有任何一行重复时返回 null。
int? repeatedLineIndex(List<String> lines) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
  final counts = <String, int>{};
  for (final l in lines) {
    final k = norm(l);
    if (k.length < 4) continue; // 太短的行（"oh"、"yeah"）不算。
    counts[k] = (counts[k] ?? 0) + 1;
  }
  String? best;
  var bestCount = 1;
  counts.forEach((k, c) {
    if (c > bestCount) {
      best = k;
      bestCount = c;
    }
  });
  if (best == null) return null;
  return lines.indexWhere((l) => norm(l) == best);
}
