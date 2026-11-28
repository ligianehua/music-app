import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../feed/feed_controller.dart';
import '../lyrics/lrc.dart';
import 'artwork.dart';
import 'heart_burst.dart';
import 'lyrics_panel.dart';
import 'comments_sheet.dart';

const _heartRed = Color(0xFFFF2D55);

/// 刷歌流里的一整屏。
///
/// 单击暂停/继续，双击红心（只加不减，和短视频一致），右侧操作栏，底部信息和进度。
class TrackPage extends StatefulWidget {
  const TrackPage({
    super.key,
    required this.item,
    required this.controller,
    required this.active,
  });

  final FeedItem item;
  final FeedController controller;

  /// 是否是当前正在播放的那一屏。
  final bool active;

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage>
    with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);
  final List<(Key, Offset)> _bursts = [];
  Offset _lastDoubleTap = Offset.zero;
  late Future<Lyrics?> _lyrics =
      widget.controller.lyricsFor(widget.item.track);

  FeedController get c => widget.controller;

  @override
  void didUpdateWidget(TrackPage old) {
    super.didUpdateWidget(old);
    if (old.item.track != widget.item.track) {
      _lyrics = c.lyricsFor(widget.item.track);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    HapticFeedback.lightImpact();
    setState(() => _bursts.add((UniqueKey(), _lastDoubleTap)));
    c.like(widget.item.track);
  }

  void _share() {
    final t = widget.item.track;
    final text = 'I found "${t.title}" by ${t.artist} on $appName'
        '${t.storeUrl == null ? '' : '\n${t.storeUrl}'}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Link copied. Paste it anywhere to share.'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.item.track;
    final media = MediaQuery.of(context);
    // 中部可用高度：减去顶栏和底部歌曲信息。小屏手机上封面跟着缩，
    // 保证封面、歌词、底部信息三者不重叠。
    const topSpace = 72.0;
    const bottomInfo = 190.0;
    const lyricsLines = 4;
    const lyricsHeight =
        LyricsPanel.lineHeight * lyricsLines + LyricsPanel.hintHeight;
    final available = media.size.height -
        media.padding.top -
        media.padding.bottom -
        topSpace -
        bottomInfo;
    final artSize = [
      media.size.width * 0.72,
      340.0,
      available - lyricsHeight - 20,
    ].reduce((a, b) => a < b ? a : b).clamp(120.0, 340.0).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 模糊封面做背景，再压一层暗色渐变保证文字可读。
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Transform.scale(scale: 1.3, child: Artwork(track: t)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x33000000), Color(0xCC000000)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),

        // 2. 整屏手势：单击暂停，双击红心。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: c.togglePlay,
          onDoubleTapDown: (d) => _lastDoubleTap = d.localPosition,
          onDoubleTap: _onDoubleTap,
        ),

        // 3. 中部：漂移的封面 + 歌词。
        // 3. 中部：封面不接收触摸（点按交给整屏手势），歌词行可以点来校准。
        //    竖滑不受影响：这里没有任何会抢拖动手势的组件。
        Padding(
          padding: EdgeInsets.only(top: media.padding.top + topSpace),
          child: Column(
            children: [
              IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: c.playing,
                  builder: (context, playing, _) => AnimatedScale(
                    scale: widget.active && !playing ? 0.9 : 1,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: _DriftingArt(
                      drift: _drift,
                      size: artSize,
                      child: Artwork(track: t),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 两侧各留 72：英文歌词较长，避免贴到右侧按钮栏。
              SizedBox(
                height: lyricsHeight,
                width: media.size.width - 144,
                child: FutureBuilder<Lyrics?>(
                  future: _lyrics,
                  builder: (context, snap) {
                    final lyrics = snap.data;
                    if (snap.connectionState != ConnectionState.done) {
                      return const _LyricsHint('Loading lyrics…');
                    }
                    if (lyrics == null) {
                      return const _LyricsHint('No lyrics available');
                    }
                    return ValueListenableBuilder<Duration?>(
                      valueListenable: c.duration,
                      builder: (context, d, _) => ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => LyricsPanel(
                          lyrics: lyrics,
                          position: c.position,
                          active: widget.active,
                          // 时长和整首歌对得上，说明播的是整首，不是试听片段。
                          fullTrack: d != null &&
                              t.durationMs > 0 &&
                              (d.inMilliseconds - t.durationMs).abs() < 3000,
                          calibratedOffset: c.lyricsOffsetFor(t),
                          trackDurationMs: t.durationMs,
                          onCalibrate: (offset) => c.calibrateLyrics(t, offset),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // 4. 暂停图标。
        if (widget.active)
          ValueListenableBuilder<bool>(
            valueListenable: c.playing,
            builder: (context, playing, _) => IgnorePointer(
              child: AnimatedOpacity(
                opacity: playing || widget.item.failed ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      size: 96, color: Colors.white70),
                ),
              ),
            ),
          ),

        if (widget.item.failed)
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: _Pill("Can't play this song. Swipe up for the next one."),
              ),
            ),
          ),

        // 5. 右侧操作栏。
        Positioned(
          right: 8,
          bottom: media.padding.bottom + 140,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final liked = c.isLiked(t);
              final saved = c.isFavorite(t);
              final comments = c.commentCount(t) ?? 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                    icon: liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? _heartRed : Colors.white,
                    label: liked ? 'Liked' : 'Like',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      c.toggleLike(t);
                    },
                  ),
                  _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: comments == 0 ? 'Comment' : '$comments',
                    onTap: () => showCommentsSheet(context, c, t),
                  ),
                  _ActionButton(
                    icon: saved ? Icons.star_rounded : Icons.star_border_rounded,
                    color: saved ? const Color(0xFFFFC53D) : Colors.white,
                    label: saved ? 'Saved' : 'Save',
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final now = await c.toggleFavorite(t);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(now
                              ? 'Saved. Find it in your profile.'
                              : 'Removed from saved songs.'),
                          duration: const Duration(seconds: 2),
                        ));
                    },
                  ),
                  _ActionButton(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: _share,
                  ),
                  _ActionButton(
                    icon: Icons.not_interested_rounded,
                    label: 'Not for me',
                    onTap: () {
                      c.dislike(widget.item);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text("Got it. You'll see less of ${t.artist}."),
                          duration: const Duration(seconds: 2),
                        ));
                    },
                  ),
                ],
              );
            },
          ),
        ),

        // 6. 底部信息 + 进度条。
        Positioned(
          left: 20,
          right: 20,
          bottom: media.padding.bottom + 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 64),
                child: _Pill(widget.item.reason, small: true),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 64),
                child: Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 64),
                child: Text(
                  [t.artist, if (t.album.isNotEmpty) t.album].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.active)
                _ProgressBar(controller: c)
              else
                const SizedBox(height: 32),
            ],
          ),
        ),

        // 7. 红心特效层。
        for (final (key, at) in _bursts)
          HeartBurst(
            key: key,
            at: at,
            onDone: () => setState(() => _bursts.removeWhere((b) => b.$1 == key)),
          ),
      ],
    );
  }
}

/// 缓慢放大、平移的封面，营造「动态封面」的感觉。
class _DriftingArt extends StatelessWidget {
  const _DriftingArt({
    required this.drift,
    required this.size,
    required this.child,
  });

  final Animation<double> drift;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(blurRadius: 40, offset: Offset(0, 16), color: Colors.black54),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: drift,
        builder: (context, child) {
          final v = Curves.easeInOut.transform(drift.value);
          return Transform.translate(
            offset: Offset((v - 0.5) * 16, (0.5 - v) * 10),
            child: Transform.scale(scale: 1.08 + v * 0.06, child: child),
          );
        },
        child: child,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(icon,
                    key: ValueKey(icon),
                    size: 30,
                    color: color,
                    shadows: const [Shadow(blurRadius: 8, color: Colors.black45)]),
              ),
              const SizedBox(height: 4),
              // 英文标签长短不一：放不下时整体缩小，不换行也不溢出。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.small = false});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 10 : 16, vertical: small ? 4 : 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: small ? 1 : 3,
        overflow: TextOverflow.ellipsis,
        textAlign: small ? TextAlign.start : TextAlign.center,
        style: TextStyle(fontSize: small ? 12 : 15, color: Colors.white),
      ),
    );
  }
}

class _LyricsHint extends StatelessWidget {
  const _LyricsHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
        ),
      );
}

/// 可拖动的细进度条。拖动时只改本地值，松手才 seek，避免拖动时来回跳。
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.controller});
  final FeedController controller;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragging;

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ValueListenableBuilder<Duration?>(
      valueListenable: c.duration,
      builder: (context, total, _) => ValueListenableBuilder<Duration>(
        valueListenable: c.position,
        builder: (context, pos, _) {
          final max = (total ?? c.previewLength).inMilliseconds.toDouble();
          final value = (_dragging ?? pos.inMilliseconds.toDouble())
              .clamp(0.0, max <= 0 ? 1.0 : max)
              .toDouble();
          return Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    max: max <= 0 ? 1 : max,
                    onChanged: (v) => setState(() => _dragging = v),
                    onChangeEnd: (v) {
                      c.seek(Duration(milliseconds: v.round()));
                      setState(() => _dragging = null);
                    },
                  ),
                ),
              ),
              Text(
                '${_fmt(Duration(milliseconds: value.round()))} / '
                '${_fmt(Duration(milliseconds: max.round()))}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
