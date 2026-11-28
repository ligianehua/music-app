import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/lyrics/chorus.dart';
import 'package:shuage/lyrics/lrc.dart';
import 'package:shuage/lyrics/offset_store.dart';
import 'package:shuage/lyrics/sync.dart';
import 'package:shuage/ui/lyrics_panel.dart';

const s = Duration(seconds: 1);

List<LyricLine> timed(List<String> texts, {int every = 10}) => [
      for (var i = 0; i < texts.length; i++)
        LyricLine(Duration(seconds: every * i), texts[i]),
    ];

void main() {
  group('estimatePreviewOffset', () {
    test('assumes the preview starts at the first chorus', () {
      final lines = timed(['intro words', 'verse words', 'the big chorus',
          'more verse', 'the big chorus']);
      expect(estimatePreviewOffset(lines), s * 20);
    });

    test('without a chorus, picks the line around 30% of the song', () {
      final lines = timed(['a line', 'b line', 'c line', 'd line', 'e line']);
      expect(estimatePreviewOffset(lines, trackDurationMs: 100000), s * 30);
    });

    test('with nothing to go on, starts at the first line', () {
      final lines = [LyricLine(s * 7, 'only line')];
      expect(estimatePreviewOffset(lines), s * 7);
      expect(estimatePreviewOffset(const []), Duration.zero);
    });

    test('tapping a line aligns it with the current position', () {
      expect(offsetForTap(LyricLine(s * 95, 'x'), s * 12), s * 83);
    });

    test('repeatedLineIndex is null when nothing repeats', () {
      expect(repeatedLineIndex(['one line', 'two line']), isNull);
      expect(chorusStartIndex(['one line', 'two line']), 0);
    });
  });

  group('LyricsOffsetStore', () {
    late LyricsOffsetStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = LyricsOffsetStore(await SharedPreferences.getInstance());
    });

    test('remembers offsets per song, including negative ones', () async {
      expect(store.get('a'), isNull);
      await store.set('a', s * 42);
      await store.set('b', -s * 3);
      expect(store.get('a'), s * 42);
      expect(store.get('b'), -s * 3);
    });

    test('keeps the most recently calibrated songs when full', () async {
      for (var i = 0; i < LyricsOffsetStore.maxEntries; i++) {
        await store.set('t$i', s);
      }
      await store.set('t0', s * 2); // 重新校准，变成最新的
      await store.set('new', s * 3);
      expect(store.get('t0'), s * 2);
      expect(store.get('t1'), isNull, reason: '最早校准的被挤掉');
      expect(store.get('new'), s * 3);
    });
  });

  group('LyricsPanel', () {
    final lyrics = Lyrics(synced: timed([
      'line zero', 'line one', 'line two', 'line three', 'line four',
      'line five', 'line six',
    ]));

    FontWeight? weightOf(WidgetTester tester, String text) {
      // 离文字最近的那一层；Material 自己也用了 AnimatedDefaultTextStyle。
      final style = tester.widget<AnimatedDefaultTextStyle>(find
          .ancestor(of: find.text(text), matching: find.byType(AnimatedDefaultTextStyle))
          .first);
      return style.style.fontWeight;
    }

    Future<ValueNotifier<Duration>> pump(
      WidgetTester tester, {
      bool active = true,
      Duration? calibrated,
      bool fullTrack = false,
      ValueChanged<Duration>? onCalibrate,
    }) async {
      final position = ValueNotifier(Duration.zero);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: LyricsPanel.lineHeight * 4 + LyricsPanel.hintHeight,
              child: LyricsPanel(
                lyrics: lyrics,
                position: position,
                active: active,
                fullTrack: fullTrack,
                calibratedOffset: calibrated,
                onCalibrate: onCalibrate,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return position;
    }

    testWidgets('scrolls with playback from the calibrated offset', (tester) async {
      final position = await pump(tester, calibrated: s * 20);
      expect(weightOf(tester, 'line two'), FontWeight.w700);
      position.value = s * 11; // 原曲 31 秒
      await tester.pump(const Duration(milliseconds: 400));
      expect(weightOf(tester, 'line three'), FontWeight.w700);
      expect(weightOf(tester, 'line two'), FontWeight.w400);
      expect(find.text('Synced · tap a line to adjust'), findsOneWidget);
    });

    testWidgets('full tracks need no offset', (tester) async {
      final position = await pump(tester, fullTrack: true, calibrated: s * 50);
      position.value = s * 10;
      await tester.pump(const Duration(milliseconds: 400));
      expect(weightOf(tester, 'line one'), FontWeight.w700);
      expect(find.textContaining('tap'), findsNothing);
    });

    testWidgets('tapping the line you hear calibrates and highlights it',
        (tester) async {
      Duration? reported;
      final position = await pump(tester, onCalibrate: (o) => reported = o);
      expect(find.text('Timing is estimated · tap the line you hear'), findsOneWidget);
      position.value = s * 5;
      await tester.pump();
      await tester.tap(find.text('line one'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(reported, s * 5, reason: '第 1 行在原曲 10 秒，此刻播到 5 秒');
      expect(weightOf(tester, 'line one'), FontWeight.w700);
      expect(find.text('Synced · tap a line to adjust'), findsOneWidget);
      // 校准后继续跟着走。
      position.value = s * 16;
      await tester.pump(const Duration(milliseconds: 400));
      expect(weightOf(tester, 'line two'), FontWeight.w700);
    });

    testWidgets('songs that are not playing are not tappable', (tester) async {
      var called = false;
      await pump(tester, active: false, onCalibrate: (_) => called = true);
      await tester.tap(find.text('line zero'), warnIfMissed: false);
      await tester.pump();
      expect(called, isFalse);
      expect(find.textContaining('tap'), findsNothing);
    });
  });
}
