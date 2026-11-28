import 'package:material_ui/material_ui.dart';

import '../feed/feed_controller.dart';

/// 「我的口味」：把推荐依据摊开给用户看，并允许一键重置。
Future<void> showTasteSheet(BuildContext context, FeedController c) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final p = c.profile;
        final artists = p.topPositive(p.artists, 8);
        final genres = p.topPositive(p.genres, 6);
        final searches = p.topPositive(p.searches, 6);
        Widget chips(List<MapEntry<String, double>> list) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in list)
                  Chip(
                    label: Text('${e.key}  ${e.value.toStringAsFixed(1)}'),
                    backgroundColor: Colors.white10,
                    labelStyle: const TextStyle(color: Colors.white),
                    side: BorderSide.none,
                  ),
              ],
            );
        const title = TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我的口味画像',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('听完、点赞、收藏、回听、搜索会加分；秒划、不感兴趣会减分。另有 20% 推荐用来探索新口味。',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 16),
                if (!p.hasPreference)
                  const Text('还在认识你，多刷几首就有了',
                      style: TextStyle(color: Colors.white70))
                else ...[
                  if (artists.isNotEmpty) ...[
                    const Text('常听歌手', style: title),
                    const SizedBox(height: 8),
                    chips(artists),
                    const SizedBox(height: 16),
                  ],
                  if (genres.isNotEmpty) ...[
                    const Text('偏好风格', style: title),
                    const SizedBox(height: 8),
                    chips(genres),
                    const SizedBox(height: 16),
                  ],
                  if (searches.isNotEmpty) ...[
                    const Text('最近搜过', style: title),
                    const SizedBox(height: 8),
                    chips(searches),
                    const SizedBox(height: 16),
                  ],
                ],
                if (p.blockedArtists.isNotEmpty) ...[
                  Text('已屏蔽：${p.blockedArtists.join('、')}',
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 16),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await c.resetTaste();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('重置口味'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
