import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shuage/feed/feed_controller.dart';
import 'package:shuage/recommend/recommender.dart';
import 'package:shuage/recommend/taste_profile.dart';
import 'package:shuage/ui/feed_page.dart';

import 'fakes.dart';

void main() {
  late FakeAudio audio;
  late FeedController c;

  Future<void> pumpFeed(WidgetTester tester) async {
    audio = FakeAudio();
    c = FeedController(
      recommender: Recommender(
        source: SequenceSource([
          [track('1', artist: '歌手甲'), track('2', artist: '歌手乙')],
        ]),
        profile: TasteProfile(),
        seeds: ['s'],
      ),
      audio: audio,
      store: await memoryStore(),
      prefetchThreshold: 0,
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: FeedPage(controller: c)));
    // 封面有无限循环的漂移动画，不能 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows the current song and plays it', (tester) async {
    await pumpFeed(tester);
    final first = c.items.first.track;
    expect(find.text(first.title), findsOneWidget);
    expect(find.text('刷歌'), findsOneWidget);
    expect(find.text('热门推荐：s'), findsOneWidget);
    expect(audio.played, [first.id]);
  });

  testWidgets('single tap pauses, tap again resumes', (tester) async {
    await pumpFeed(tester);
    await tester.tapAt(const Offset(195, 300));
    // 单击要等双击判定超时才触发。
    await tester.pump(const Duration(milliseconds: 400));
    expect(audio.isPlaying, isFalse);
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(audio.isPlaying, isTrue);
  });

  testWidgets('double tap likes and shows a heart burst', (tester) async {
    await pumpFeed(tester);
    final first = c.items.first.track;
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.isLiked(first), isTrue);
    expect(find.text('已喜欢'), findsOneWidget);
    expect(audio.isPlaying, isTrue, reason: '双击不应触发暂停');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('swiping up switches to the next song', (tester) async {
    await pumpFeed(tester);
    final second = c.items[1].track;
    await tester.fling(find.byType(PageView), const Offset(0, -500), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(audio.played.last, second.id);
    expect(c.index, 1);
  });

  testWidgets('不感兴趣 removes the song and shows feedback', (tester) async {
    await pumpFeed(tester);
    final first = c.items.first.track;
    await tester.tap(find.text('不感兴趣').first);
    await tester.pump();
    expect(find.text('好的，少推 ${first.artist}'), findsOneWidget);
    expect(c.profile.blockedArtists, {first.artist});
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.index, 1);
  });
}
