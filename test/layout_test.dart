import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/account/user.dart';
import 'package:shuage/feed/feed_controller.dart';
import 'package:shuage/models/track.dart';
import 'package:shuage/recommend/recommender.dart';
import 'package:shuage/recommend/taste_profile.dart';
import 'package:shuage/social/comment.dart';
import 'package:shuage/ui/auth_page.dart';
import 'package:shuage/ui/comments_sheet.dart';
import 'package:shuage/ui/feed_page.dart';
import 'package:shuage/ui/me_page.dart';
import 'package:shuage/ui/preferences_page.dart';
import 'package:shuage/ui/search_page.dart';

import 'fakes.dart';

/// 英文版排版检查：小屏手机和放大字体下，任何溢出都会让测试失败。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sizes = {
    'small phone': Size(320, 568),
    'regular phone': Size(390, 844),
  };
  const textScales = [1.0, 1.3];

  // 故意用长名字，逼出排版问题。
  final longTrack = Track(
    id: 'long',
    title: 'A Very Long Song Title That Keeps Going (Acoustic Version) [Live]',
    artist: 'Ben&Ben feat. Moira Dela Torre and Zack Tabudlo',
    album: 'An Unreasonably Long Album Name for Testing Layout',
    artworkUrl: '',
    previewUrl: 'https://example.com/long.m4a',
  );
  final longUser = AppUser(
    id: 'user-1',
    username: 'averylongusername20',
    createdAt: DateTime(2026, 11, 1),
    preferences: const UserPreferences(languages: {'English'}),
  );

  Future<void> pumpAt(WidgetTester tester, Size size, double scale,
      Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<FeedController> feed() async {
    final store = await memoryStore();
    final prefs = await SharedPreferences.getInstance();
    final c = FeedController(
      user: longUser,
      recommender: Recommender(
        source: FakeSource({}, fallback: [longTrack, track('2', artist: 'B')]),
        profile: TasteProfile()
          ..record(track('x', artist: 'Moira Dela Torre', genre: 'Pop'), Signal.like)
          ..recordSearch('acoustic love songs')
          ..record(track('y', artist: 'Some Artist'), Signal.dislike),
        preferences: const UserPreferences(languages: {'English'}),
        seeds: ['Something With A Really Long Seed Name'],
      ),
      audio: FakeAudio(),
      store: store,
      comments: LocalCommentStore(prefs),
    );
    return c;
  }

  for (final entry in sizes.entries) {
    for (final scale in textScales) {
      final label = '${entry.key}, text x$scale';
      final size = entry.value;

      testWidgets('login and sign-up fit ($label)', (tester) async {
        await pumpAt(tester, size, scale, AuthPage(auth: await memoryAuth()));
        await tester.tap(find.text("Don't have an account? Sign up"));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Sign up'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('preferences fit ($label)', (tester) async {
        await pumpAt(tester, size, scale,
            const PreferencesPage(onboarding: true));
        expect(tester.takeException(), isNull);
      });

      testWidgets('feed with long titles fits ($label)', (tester) async {
        final c = await feed();
        await pumpAt(tester, size, scale,
            FeedPage(controller: c, auth: await memoryAuth()));
        expect(find.text('Not for me'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await c.toggleLike(c.current!.track);
        await c.toggleFavorite(c.current!.track);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('comments sheet fits ($label)', (tester) async {
        final c = await feed();
        await c.init();
        await c.addComment(longTrack,
            'This chorus is stuck in my head all week, thank you for recommending it!');
        await pumpAt(tester, size, scale,
            Scaffold(body: CommentsSheet(controller: c, track: longTrack)));
        expect(find.textContaining('(you)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('profile and search fit ($label)', (tester) async {
        final c = await feed();
        await c.init();
        await c.toggleFavorite(longTrack);
        await pumpAt(tester, size, scale,
            MePage(controller: c, auth: await memoryAuth()));
        expect(tester.takeException(), isNull);
        await c.recordSearch('Ben&Ben');
        await c.recordSearch('an extremely long search query about acoustic songs');
        await pumpAt(tester, size, scale, SearchPage(controller: c));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
