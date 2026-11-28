import 'package:material_ui/material_ui.dart';

import '../account/auth_service.dart';
import '../feed/feed_controller.dart';
import 'comments_sheet.dart' show monthName;
import '../models/track.dart';
import 'preferences_page.dart';
import 'search_page.dart';

/// 「我的」：账号信息、收藏、点赞、偏好设置、退出登录。
///
/// 点一首歌返回该歌和来源说明，刷歌流会立刻播放它。
class MePage extends StatelessWidget {
  const MePage({super.key, required this.controller, required this.auth});
  final FeedController controller;
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final user = controller.user;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Profile'),
          actions: [
            IconButton(
              tooltip: 'Music preferences',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () async {
                final prefs = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PreferencesPage(
                      initial: auth.currentUser?.preferences ?? user.preferences,
                      title: 'Edit preferences',
                      submitLabel: 'Save',
                    ),
                  ),
                );
                if (prefs == null) return;
                await auth.updatePreferences(prefs);
                controller.updatePreferences(prefs);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Saved. New songs will follow your preferences.')));
                }
              },
            ),
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Log out?'),
                    content: const Text(
                        'Your saved songs and likes will be here when you log back in.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Log out')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                Navigator.of(context).pop();
                await auth.logout();
              },
            ),
          ],
        ),
        // 账号信息放在正文而不是顶栏里：高度随字体大小伸缩，不会被截断。
        body: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF31C27C),
                child: Text(user.username.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 20, color: Colors.white)),
              ),
              title: Text(user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'Joined ${monthName(user.createdAt.month)} ${user.createdAt.year} · Local account',
                  style: const TextStyle(color: Colors.white54)),
            ),
            const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [Tab(text: 'Saved'), Tab(text: 'Liked')],
            ),
            Expanded(
              child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => TabBarView(
                children: [
                  _TrackList(
                    tracks: controller.favorites,
                    empty: 'Tap the star on a song to save it here.',
                    reason: 'From your saved songs',
                    trailing: (t) => IconButton(
                      tooltip: 'Remove from saved',
                      icon: const Icon(Icons.star_rounded, color: Color(0xFFFFC53D)),
                      onPressed: () => controller.toggleFavorite(t),
                    ),
                  ),
                  _TrackList(
                    tracks: controller.liked,
                    empty: 'Double-tap a playing song to like it.',
                    reason: 'From your likes',
                    trailing: (t) => IconButton(
                      tooltip: 'Unlike',
                      icon: const Icon(Icons.favorite, color: Color(0xFFFF2D55)),
                      onPressed: () => controller.toggleLike(t),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 从「我的」里选中的一首歌和来源说明。
typedef PickedTrack = ({Track track, String reason});

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.empty,
    required this.reason,
    required this.trailing,
  });

  final List<Track> tracks;
  final String empty;
  final String reason;
  final Widget Function(Track) trailing;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(empty,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) => TrackTile(
        track: tracks[i],
        trailing: trailing(tracks[i]),
        onTap: () => Navigator.of(context)
            .pop<PickedTrack>((track: tracks[i], reason: reason)),
      ),
    );
  }
}
