import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account/local_auth_service.dart';
import 'app.dart';
import 'audio/just_audio_engine.dart';
import 'audio/now_playing.dart';
import 'audio/system_media_session.dart';
import 'data/itunes_source.dart';
import 'data/lyrics_source.dart';
import 'data/trending_source.dart';
import 'demo/demo_mode.dart';
import 'social/comment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final services = AppServices(
    prefs: prefs,
    auth: LocalAuthService(prefs),
    tracks: kDemoMode ? DemoSource() : ItunesSource(),
    trending: kDemoMode ? null : AppleChartSource(),
    lyrics: kDemoMode ? DemoLyricsSource() : LrclibSource(),
    comments: LocalCommentStore(prefs),
    audioFactory: kDemoMode ? DemoAudioEngine.new : JustAudioEngine.new,
    session: await _initMediaSession(),
  );
  runApp(ShuageApp(services: services));
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
    debugPrint('Audio session setup failed: $e');
  }
  try {
    return await SystemMediaSession.init();
  } catch (e) {
    debugPrint('Lock screen controls unavailable: $e');
    return null;
  }
}
