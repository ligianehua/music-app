import 'package:material_ui/material_ui.dart';

import '../data/track_source.dart';
import '../feed/feed_controller.dart';
import '../models/track.dart';
import 'artwork.dart';

/// 搜索页：搜歌名或歌手，点一首立刻播放；搜过的词会影响之后的推荐。
///
/// 返回用户点选的歌，没选则返回 null。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});
  final FeedController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _input = TextEditingController();
  Future<List<Track>>? _results;
  String _term = '';

  FeedController get c => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _search(String raw) {
    final term = raw.trim();
    if (term.isEmpty) return;
    _input.text = term;
    FocusScope.of(context).unfocus();
    c.recordSearch(term);
    setState(() {
      _term = term;
      _results = c.recommender.source.search(term, limit: 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _input,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '搜歌名、歌手',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            isDense: true,
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _search(_input.text),
            child: const Text('搜索'),
          ),
        ],
      ),
      body: _results == null ? _history() : _resultList(),
    );
  }

  Widget _history() {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final history = c.searchHistory;
        if (history.isEmpty) {
          return const Center(
            child: Text('搜过的歌会让推荐更懂你',
                style: TextStyle(color: Colors.white38)),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('搜索历史',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: c.clearSearchHistory,
                    child: const Text('清空'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in history)
                    ActionChip(
                      label: Text(h),
                      onPressed: () => _search(h),
                      backgroundColor: Colors.white10,
                      labelStyle: const TextStyle(color: Colors.white),
                      side: BorderSide.none,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resultList() {
    return FutureBuilder<List<Track>>(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final e = snap.error;
          return _Message(e is TrackSourceException ? e.message : '搜索失败：$e',
              onRetry: () => _search(_term));
        }
        final tracks = snap.data ?? const [];
        if (tracks.isEmpty) {
          return _Message('没找到「$_term」相关的歌，换个说法试试');
        }
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) => TrackTile(
            track: tracks[i],
            onTap: () => Navigator.of(context).pop(tracks[i]),
          ),
        );
      },
    );
  }
}

/// 列表里的一首歌：封面、歌名、歌手。
class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, this.onTap, this.trailing});
  final Track track;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 48, height: 48, child: Artwork(track: track)),
      ),
      title: Text(track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white)),
      subtitle: Text(
          [track.artist, if (track.album.isNotEmpty) track.album].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54)),
      trailing: trailing ??
          const Icon(Icons.play_circle_outline_rounded, color: Colors.white54),
      onTap: onTap,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ],
          ),
        ),
      );
}
