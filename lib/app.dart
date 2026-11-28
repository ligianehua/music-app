import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account/auth_service.dart';
import 'app_info.dart';
import 'account/user.dart';
import 'audio/audio_engine.dart';
import 'audio/now_playing.dart';
import 'data/library_store.dart';
import 'data/lyrics_source.dart';
import 'data/track_source.dart';
import 'data/trending_source.dart';
import 'feed/feed_controller.dart';
import 'recommend/recommender.dart';
import 'social/comment.dart';
import 'ui/auth_page.dart';
import 'ui/feed_page.dart';
import 'ui/preferences_page.dart';

/// 刷歌 App 依赖的外部服务。测试时可以整体替换。
class AppServices {
  const AppServices({
    required this.prefs,
    required this.auth,
    required this.tracks,
    required this.audioFactory,
    this.trending,
    this.lyrics,
    this.comments,
    this.session,
  });

  final SharedPreferences prefs;
  final AuthService auth;
  final TrackSource tracks;

  /// 每个账号登录时新建一个播放引擎，退出时销毁，账号之间互不串台。
  final AudioEngine Function() audioFactory;
  final TrendingSource? trending;
  final LyricsSource? lyrics;
  final CommentStore? comments;
  final NowPlayingSession? session;
}

class ShuageApp extends StatelessWidget {
  const ShuageApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      // 网页版在电脑上也能用鼠标、触控板拖着刷。
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF31C27C),
        scaffoldBackgroundColor: Colors.black,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: AuthGate(services: services),
    );
  }
}

/// 按登录状态决定显示什么：登录页、首次偏好设置、或刷歌流。
///
/// 每个账号一套独立的刷歌流和播放引擎；换账号时旧的全部销毁。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.services});
  final AppServices services;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  FeedController? _feed;
  AudioEngine? _audio;

  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    s.auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() => setState(() {});

  /// 为 [user] 准备刷歌流；同一个账号重复调用会复用。
  FeedController _feedFor(AppUser user) {
    final existing = _feed;
    if (existing != null && existing.user.id == user.id) return existing;
    _retire();
    final store = LibraryStore(s.prefs, userId: user.id);
    final audio = s.audioFactory();
    final feed = FeedController(
      user: user,
      recommender: Recommender(
        source: s.tracks,
        trending: s.trending,
        profile: store.loadProfile(),
        preferences: user.preferences,
      ),
      audio: audio,
      store: store,
      comments: s.comments,
      lyricsSource: s.lyrics,
      session: s.session,
    );
    _feed = feed;
    _audio = audio;
    return feed;
  }

  /// 停用当前账号的刷歌流：立刻停播，等这一帧画完、旧页面拆掉后再销毁。
  void _retire() {
    final feed = _feed;
    final audio = _audio;
    if (feed == null) return;
    _feed = null;
    _audio = null;
    feed.pause();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      feed.dispose();
      audio?.dispose();
    });
  }

  @override
  void dispose() {
    s.auth.removeListener(_onAuthChanged);
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = s.auth.currentUser;
    if (user == null) {
      _retire();
      return AuthPage(auth: s.auth);
    }
    if (user.needsOnboarding) {
      return PreferencesPage(
        key: ValueKey('onboarding-${user.id}'),
        onboarding: true,
        onSubmit: s.auth.updatePreferences,
      );
    }
    final feed = _feedFor(user);
    return FeedPage(key: ValueKey(user.id), controller: feed, auth: s.auth);
  }
}
