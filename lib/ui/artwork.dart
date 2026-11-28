import 'package:material_ui/material_ui.dart';

import '../models/track.dart';

/// 封面。没有图或加载失败时，按歌曲 id 生成一个稳定的渐变色块。
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.track, this.fit = BoxFit.cover});

  final Track track;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(track: track);
    if (track.artworkUrl.isEmpty) return placeholder;
    return Image.network(
      track.artworkUrl,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? placeholder : child,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final hue = (track.id.hashCode % 360).abs().toDouble();
    final a = HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 60) % 360, 0.6, 0.22).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 72, color: Colors.white54),
      ),
    );
  }
}
