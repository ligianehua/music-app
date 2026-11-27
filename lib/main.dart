import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';

import 'audio/just_audio_engine.dart';
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
