import 'package:material_ui/material_ui.dart';

import '../feed/feed_controller.dart';
import '../models/track.dart';
import 'artwork.dart';

/// 「我喜欢」歌单。点一首会返回刷歌流，并把它插到下一张。
class LikedPage extends StatelessWidget {
  const LikedPage({super.key, required this.controller});
  final FeedController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final liked = controller.liked;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('我喜欢 · ${liked.length}'),
          ),
          body: liked.isEmpty
              ? const Center(
                  child: Text('双击正在播的歌，就能收进这里',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  itemCount: liked.length,
                  itemBuilder: (context, i) {
                    final Track t = liked[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                            width: 48, height: 48, child: Artwork(track: t)),
                      ),
                      title: Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54)),
                      trailing: IconButton(
                        tooltip: '取消喜欢',
                        icon: const Icon(Icons.favorite,
                            color: Color(0xFFFF2D55)),
                        onPressed: () => controller.toggleLike(t),
                      ),
                      onTap: () => Navigator.of(context).pop(t),
                    );
                  },
                ),
        );
      },
    );
  }
}
