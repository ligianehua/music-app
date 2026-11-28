import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuage/account/user.dart';
import 'package:shuage/data/library_store.dart';
import 'package:shuage/recommend/taste_profile.dart';
import 'package:shuage/social/comment.dart';
import 'package:shuage/ui/comments_sheet.dart';

import 'fakes.dart';

void main() {
  late SharedPreferences prefs;
  final alice = AppUser(id: 'a', username: '阿丽', createdAt: DateTime(2026));
  final bob = AppUser(id: 'b', username: '阿博', createdAt: DateTime(2026));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('LibraryStore', () {
    test('each account keeps its own likes, favorites and profile', () async {
      final a = LibraryStore(prefs, userId: 'a');
      final b = LibraryStore(prefs, userId: 'b');
      await a.saveLiked([track('1')]);
      await a.saveFavorites([track('2')]);
      await a.saveProfile(TasteProfile()..record(track('1', artist: 'X'), Signal.like));
      expect(b.loadLiked(), isEmpty);
      expect(b.loadFavorites(), isEmpty);
      expect(b.loadProfile().artists, isEmpty);
      expect(a.loadLiked(), [track('1')]);
      expect(a.loadFavorites(), [track('2')]);
      expect(a.loadProfile().artists['X'], 2.0);
    });

    test('search history dedupes, keeps newest first and is capped', () async {
      final s = LibraryStore(prefs, userId: 'a');
      await s.addSearch('A');
      await s.addSearch('B');
      expect(await s.addSearch(' A '), ['A', 'B']);
      expect(await s.addSearch('  '), ['A', 'B']);
      for (var i = 0; i < 30; i++) {
        await s.addSearch('t$i');
      }
      expect(s.loadSearchHistory(), hasLength(LibraryStore.maxHistory));
      expect(s.loadSearchHistory().first, 't29');
      await s.clearSearchHistory();
      expect(s.loadSearchHistory(), isEmpty);
    });
  });

  group('TasteProfile.recordSearch', () {
    test('recent searches outweigh older ones and old ones fade out', () {
      final p = TasteProfile();
      p.recordSearch('老歌');
      for (var i = 0; i < 12; i++) {
        p.recordSearch('新歌');
      }
      expect(p.searches['新歌'], TasteProfile.maxScore);
      expect(p.searches.containsKey('老歌'), isFalse);
      expect(p.hasPreference, isTrue);
    });

    test('keeps at most maxSearches terms', () {
      final p = TasteProfile();
      for (var i = 0; i < 40; i++) {
        p.recordSearch('词$i');
      }
      expect(p.searches.length, lessThanOrEqualTo(TasteProfile.maxSearches));
      expect(p.searches.containsKey('词39'), isTrue);
    });

    test('is saved with the profile', () {
      final p = TasteProfile()..recordSearch('陈奕迅');
      expect(TasteProfile.fromJson(p.toJson()).searches.keys, ['陈奕迅']);
    });
  });

  group('LocalCommentStore', () {
    test('comments are shared across accounts on this phone, newest first', () async {
      var now = DateTime(2026, 11, 28, 12);
      final store = LocalCommentStore(prefs, clock: () => now);
      await store.add('song', alice, '第一');
      now = now.add(const Duration(minutes: 1));
      await store.add('song', bob, '第二');
      final list = await store.list('song');
      expect(list.map((c) => c.text), ['第二', '第一']);
      expect(list.first.username, '阿博');
      expect(await store.list('other'), isEmpty);
    });

    test('only the author can delete a comment', () async {
      final store = LocalCommentStore(prefs);
      final c = await store.add('song', alice, '我的');
      expect(() => store.delete(c, bob), throwsStateError);
      await store.delete(c, alice);
      expect(await store.list('song'), isEmpty);
    });

    test('rejects empty and overly long comments', () async {
      final store = LocalCommentStore(prefs);
      expect(() => store.add('song', alice, '   '), throwsArgumentError);
      expect(() => store.add('song', alice, 'x' * (maxCommentLength + 1)),
          throwsArgumentError);
    });
  });

  test('relativeTime reads naturally', () {
    final now = DateTime(2026, 11, 28, 12);
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), '5m ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now), '3h ago');
    expect(relativeTime(now.subtract(const Duration(days: 2)), now), '2d ago');
    expect(relativeTime(DateTime(2026, 1, 5), now), 'Jan 5, 2026');
  });
}
