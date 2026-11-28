import 'package:flutter_test/flutter_test.dart';
import 'package:shuage/data/lyrics_source.dart';
import 'package:shuage/lyrics/chorus.dart';
import 'package:shuage/lyrics/lrc.dart';
import 'package:shuage/models/track.dart';

void main() {
  group('parseLrc', () {
    test('parses fractions, multi tags, skips metadata and blanks', () {
      final lines = parseLrc('''
[ar:周杰伦]
[ti:晴天]
[00:01.5]第一行
[00:10.05][01:00.123]重复行
[00:20.00]
[00:15]无小数
''');
      expect(lines, const [
        LyricLine(Duration(milliseconds: 1500), '第一行'),
        LyricLine(Duration(milliseconds: 10050), '重复行'),
        LyricLine(Duration(seconds: 15), '无小数'),
        LyricLine(Duration(milliseconds: 60123), '重复行'),
      ]);
    });

    test('lyricIndexAt finds the active line', () {
      final lines = parseLrc('[00:05.00]a\n[00:10.00]b\n[00:20.00]c');
      expect(lyricIndexAt(lines, const Duration(seconds: 1)), -1);
      expect(lyricIndexAt(lines, const Duration(seconds: 5)), 0);
      expect(lyricIndexAt(lines, const Duration(seconds: 19)), 1);
      expect(lyricIndexAt(lines, const Duration(minutes: 3)), 2);
      expect(lyricIndexAt(const [], Duration.zero), -1);
    });
  });

  group('chorusStartIndex', () {
    test('points at the first occurrence of the most repeated line', () {
      final lines = [
        '故事的小黄花',
        '从出生那年就飘着',
        '刮风这天 我试过握着你手',
        '但偏偏 雨渐渐 大到我看你不见',
        '还要多久 我才能在你身边',
        '刮风这天，我试过握着你手！',
        '但偏偏 雨渐渐 大到我看你不见',
      ];
      expect(chorusStartIndex(lines), 2);
    });

    test('returns 0 when nothing repeats or lines are too short', () {
      expect(chorusStartIndex(['a', 'b', 'oh', 'oh']), 0);
      expect(chorusStartIndex(const []), 0);
    });
  });

  group('pickBestLyrics', () {
    const t = Track(
      id: '1',
      title: 't',
      artist: 'a',
      album: '',
      artworkUrl: '',
      previewUrl: '',
      durationMs: 200000,
    );

    test('prefers synced lyrics, then closest duration', () {
      final l = pickBestLyrics([
        {'duration': 200, 'plainLyrics': 'plain only'},
        {'duration': 260, 'syncedLyrics': '[00:01.00]far'},
        {'duration': 201, 'syncedLyrics': '[00:01.00]close'},
      ], t)!;
      expect(l.synced!.single.text, 'close');
    });

    test('falls back to plain lyrics and drops blank lines', () {
      final l = pickBestLyrics([
        {'plainLyrics': 'one\n\n two \n'},
      ], t)!;
      expect(l.synced, isNull);
      expect(l.lines, ['one', 'two']);
    });

    test('returns null for empty candidates or instrumental entries', () {
      expect(pickBestLyrics([], t), isNull);
      expect(pickBestLyrics([{'instrumental': true}], t), isNull);
    });
  });
}
