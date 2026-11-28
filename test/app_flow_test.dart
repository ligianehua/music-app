import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/app.dart';
import 'package:shuage/social/comment.dart';
import 'package:shuage/ui/auth_page.dart';
import 'package:shuage/ui/feed_page.dart';
import 'package:shuage/ui/preferences_page.dart';

import 'fakes.dart';

void main() {
  late FakeAudio lastAudio;
  late FakeSource source;

  Future<AppServices> services() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    source = FakeSource({}, fallback: [
      track('a', artist: '歌手甲'),
      track('b', artist: '歌手乙'),
    ]);
    return AppServices(
      prefs: prefs,
      auth: await memoryAuth(),
      tracks: source,
      comments: LocalCommentStore(prefs),
      audioFactory: () => lastAudio = FakeAudio(),
    );
  }

  Future<void> pumpApp(WidgetTester tester, AppServices s) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShuageApp(services: s));
    await tester.pump();
  }

  /// 刷歌页有无限循环的封面动画，不能 pumpAndSettle。
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('register, pick preferences, then land in the feed', (tester) async {
    final s = await services();
    await pumpApp(tester, s);
    expect(find.byType(AuthPage), findsOneWidget);

    await tester.tap(find.text('没有账号？注册一个'));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '小明');
    await tester.enterText(fields.at(1), 'abc123');
    await tester.enterText(fields.at(2), 'abc124');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pump();
    expect(find.text('两次输入的密码不一样'), findsOneWidget);

    await tester.enterText(fields.at(2), 'abc123');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pumpAndSettle();
    expect(find.byType(PreferencesPage), findsOneWidget);
    expect(find.text('至少选一项'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '粤语'));
    await tester.pump();
    await tester.tap(find.text('开始刷歌'));
    await tester.pump();
    await settleFrames(tester);

    expect(find.byType(FeedPage), findsOneWidget);
    expect(s.auth.currentUser!.preferences.languages, {'粤语'});
    expect(lastAudio.played, hasLength(1));
    expect(source.terms, isNotEmpty);
  });

  testWidgets('skipping preferences still gets you into the feed', (tester) async {
    final s = await services();
    await s.auth.register('小红', 'abc123');
    await pumpApp(tester, s);
    expect(find.byType(PreferencesPage), findsOneWidget);
    await tester.tap(find.text('跳过，什么都推'));
    await tester.pump();
    await settleFrames(tester);
    expect(find.byType(FeedPage), findsOneWidget);
  });

  testWidgets('logging out stops playback and returns to the login page',
      (tester) async {
    final s = await services();
    await s.auth.register('小明', 'abc123');
    await s.auth.updatePreferences(
        (s.auth.currentUser!.preferences).copyWith(languages: {'华语'}));
    await pumpApp(tester, s);
    await settleFrames(tester);
    expect(find.byType(FeedPage), findsOneWidget);
    final audio = lastAudio;
    expect(audio.isPlaying, isTrue);

    await tester.tap(find.byTooltip('我的'));
    await settleFrames(tester);
    expect(find.text('小明'), findsOneWidget);
    await tester.tap(find.byTooltip('退出登录'));
    await settleFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, '退出'));
    await settleFrames(tester);

    expect(find.byType(AuthPage), findsOneWidget);
    expect(audio.isPlaying, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each account sees only its own favorites', (tester) async {
    final s = await services();
    await s.auth.register('用户甲', 'abc123');
    await s.auth.updatePreferences(
        s.auth.currentUser!.preferences.copyWith(languages: {'华语'}));
    await pumpApp(tester, s);
    await settleFrames(tester);
    await tester.tap(find.text('收藏').first);
    await settleFrames(tester);
    expect(find.text('已收藏'), findsOneWidget);

    await s.auth.logout();
    await settleFrames(tester);
    await s.auth.register('用户乙', 'abc123');
    await s.auth.updatePreferences(
        s.auth.currentUser!.preferences.copyWith(languages: {'华语'}));
    await settleFrames(tester);
    expect(find.byType(FeedPage), findsOneWidget);
    expect(find.text('已收藏'), findsNothing);
  });

  testWidgets('a search result plays right away', (tester) async {
    final s = await services();
    await s.auth.register('小明', 'abc123');
    await s.auth.updatePreferences(
        s.auth.currentUser!.preferences.copyWith(languages: {'华语'}));
    await pumpApp(tester, s);
    await settleFrames(tester);

    await tester.tap(find.byTooltip('搜索'));
    await settleFrames(tester);
    await tester.enterText(find.byType(TextField), '晴天');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settleFrames(tester);
    expect(source.terms.last, '晴天');
    await tester.tap(find.text(source.fallback.first.title).last);
    await settleFrames(tester);

    expect(find.byType(FeedPage), findsOneWidget);
    expect(lastAudio.played.last, source.fallback.first.id);
  });
}
