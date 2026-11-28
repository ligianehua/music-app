import 'package:material_ui/material_ui.dart';

import '../account/auth_service.dart';
import '../feed/feed_controller.dart';
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
          title: const Text('我的'),
          actions: [
            IconButton(
              tooltip: '听歌偏好',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () async {
                final prefs = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PreferencesPage(
                      initial: auth.currentUser?.preferences ?? user.preferences,
                      title: '修改听歌偏好',
                      submitLabel: '保存',
                    ),
                  ),
                );
                if (prefs == null) return;
                await auth.updatePreferences(prefs);
                controller.updatePreferences(prefs);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已保存，接下来的推荐会按新偏好来')));
                }
              },
            ),
            IconButton(
              tooltip: '退出登录',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('退出登录？'),
                    content: const Text('你的收藏和点赞会保留，下次登录还在。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('退出')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                Navigator.of(context).pop();
                await auth.logout();
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF31C27C),
                    child: Text(user.username.characters.first,
                        style: const TextStyle(fontSize: 20, color: Colors.white)),
                  ),
                  title: Text(user.username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${user.createdAt.year} 年 ${user.createdAt.month} 月加入 · 本机账号',
                      style: const TextStyle(color: Colors.white54)),
                ),
                const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  tabs: [Tab(text: '收藏'), Tab(text: '点赞')],
                ),
              ],
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => TabBarView(
            children: [
              _TrackList(
                tracks: controller.favorites,
                empty: '点歌曲右侧的星星，就能收藏到这里',
                reason: '来自我的收藏',
                trailing: (t) => IconButton(
                  tooltip: '取消收藏',
                  icon: const Icon(Icons.star_rounded, color: Color(0xFFFFC53D)),
                  onPressed: () => controller.toggleFavorite(t),
                ),
              ),
              _TrackList(
                tracks: controller.liked,
                empty: '双击正在播的歌就能点赞',
                reason: '来自我的点赞',
                trailing: (t) => IconButton(
                  tooltip: '取消点赞',
                  icon: const Icon(Icons.favorite, color: Color(0xFFFF2D55)),
                  onPressed: () => controller.toggleLike(t),
                ),
              ),
            ],
          ),
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
          child: Text(empty, style: const TextStyle(color: Colors.white54)));
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
