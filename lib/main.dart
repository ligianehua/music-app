import 'dart:ui' show PointerDeviceKind;

import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart';

import 'audio/just_audio_engine.dart';
import 'audio/now_playing.dart';
import 'audio/system_media_session.dart';
import 'data/itunes_source.dart';
import 'data/library_store.dart';
import 'data/lyrics_source.dart';
import 'demo/demo_mode.dart';
import 'feed/feed_controller.dart';
import 'recommend/recommender.dart';
import 'ui/feed_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LibraryStore.open();
  final controller = FeedController(
    session: await _initMediaSession(),
    recommender: Recommender(
      source: kDemoMode ? DemoSource() : ItunesSource(),
      profile: store.loadProfile(),
    ),
    audio: kDemoMode ? DemoAudioEngine() : JustAudioEngine(),
    store: store,
    lyricsSource: kDemoMode ? DemoLyricsSource() : LrclibSource(),
  );
  runApp(ShuageApp(controller: controller));
}

/// 接入系统媒体会话：锁屏控制、通知栏播放器、耳机线控。
///
/// 失败时（比如在不支持的桌面平台上）返回 null，App 照常可用，只是没有锁屏控制。
Future<NowPlayingSession?> _initMediaSession() async {
  try {
    // 声明为音乐播放：iOS 静音键下也出声，来电等打断后由系统协调。
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    debugPrint('音频会话配置失败：$e');
  }
  try {
    return await SystemMediaSession.init();
  } catch (e) {
    debugPrint('锁屏控制初始化失败：$e');
    return null;
  }
}

class ShuageApp extends StatelessWidget {
  const ShuageApp({super.key, required this.controller});
  final FeedController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '刷歌',
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
      home: FeedPage(controller: controller),
    );
  }
}
