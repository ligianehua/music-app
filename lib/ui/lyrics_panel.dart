import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../lyrics/chorus.dart';
import '../lyrics/lrc.dart';

/// 卡片中部的歌词面板。
///
/// - 播放的是整首歌且有时间轴：逐行高亮并自动滚动；
/// - 播放的是试听片段：无法对齐时间，直接停在估算的副歌位置。
///
/// 面板不响应手势，避免和外层竖滑翻页抢手势。
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.position,
    required this.synced,
  });

  final Lyrics lyrics;
  final ValueListenable<Duration> position;

  /// 为 true 时按 [position] 逐行高亮。
  final bool synced;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const lineHeight = 30.0;
  final _scroll = ScrollController();
  int _current = -1;

  List<String> get _lines => widget.lyrics.lines;
  bool get _canSync => widget.synced && widget.lyrics.synced != null;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canSync) _jumpTo(chorusStartIndex(_lines), animate: false);
    });
  }

  @override
  void didUpdateWidget(LyricsPanel old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onTick);
      widget.position.addListener(_onTick);
    }
  }

  void _onTick() {
    if (!_canSync) return;
    final i = lyricIndexAt(widget.lyrics.synced!, widget.position.value);
    if (i != _current) {
      setState(() => _current = i);
      _jumpTo(i < 0 ? 0 : i);
    }
  }

  void _jumpTo(int i, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final target = (i * lineHeight)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    if (animate) {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onTick);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, 0.2, 0.75, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scroll,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: lineHeight),
        itemExtent: lineHeight,
        itemCount: _lines.length,
        itemBuilder: (context, i) {
          final active = _canSync && i == _current;
          return Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: active ? 17 : 15,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? Colors.white : Colors.white70,
                height: 1.2,
              ),
              child: Text(
                _lines[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }
}
