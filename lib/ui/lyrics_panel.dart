import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../lyrics/chorus.dart';
import '../lyrics/lrc.dart';
import '../lyrics/sync.dart';

/// 卡片中部的歌词面板。
///
/// - 有时间轴的歌词：跟着播放逐行高亮、自动滚动。
///   播整首歌时直接对齐；播试听片段时起点是估算的（见 [estimatePreviewOffset]），
///   点一下正在唱的那一行就能校准。
/// - 没有时间轴的歌词：停在估算的副歌位置。
///
/// 面板本身不能拖动，竖滑永远是切歌。
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.position,
    required this.active,
    this.fullTrack = false,
    this.calibratedOffset,
    this.trackDurationMs = 0,
    this.onCalibrate,
  });

  static const lineHeight = 30.0;

  /// 底部提示行的高度。
  static const hintHeight = 18.0;

  final Lyrics lyrics;
  final ValueListenable<Duration> position;

  /// 是否是正在播放的那一屏。不在播的屏只静态显示起始位置。
  final bool active;

  /// 正在播整首歌：播放位置就是原曲时刻，不需要偏移。
  final bool fullTrack;

  /// 用户校准过的偏移；为 null 时用估算值。
  final Duration? calibratedOffset;
  final int trackDurationMs;

  /// 用户点了某一行，算出了新的偏移。
  final ValueChanged<Duration>? onCalibrate;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const lineHeight = LyricsPanel.lineHeight;
  final _scroll = ScrollController();
  int _current = -1;

  /// 用户刚点过、还没回传到 [LyricsPanel.calibratedOffset] 的偏移。
  Duration? _localOffset;
  late Duration _estimate = _computeEstimate();

  List<LyricLine>? get _timed => widget.lyrics.synced;
  List<String> get _lines => widget.lyrics.lines;
  bool get _hasTiming => _timed != null && _timed!.isNotEmpty;

  Duration _computeEstimate() => _timed == null
      ? Duration.zero
      : estimatePreviewOffset(_timed!, trackDurationMs: widget.trackDurationMs);

  /// 试听第 0 秒对应原曲的哪个时刻。
  Duration get _offset => widget.fullTrack
      ? Duration.zero
      : (_localOffset ?? widget.calibratedOffset ?? _estimate);

  bool get _calibrated =>
      widget.fullTrack || _localOffset != null || widget.calibratedOffset != null;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hasTiming) {
        _sync(animate: false);
      } else {
        _scrollTo(chorusStartIndex(_lines), animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(LyricsPanel old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onTick);
      widget.position.addListener(_onTick);
    }
    if (old.lyrics != widget.lyrics ||
        old.trackDurationMs != widget.trackDurationMs) {
      _estimate = _computeEstimate();
    }
    if (widget.calibratedOffset != null) _localOffset = null;
    if (old.active != widget.active || old.fullTrack != widget.fullTrack) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
  }

  void _onTick() {
    if (widget.active) _sync();
  }

  /// 按「偏移 + 播放位置」找出正在唱的行，并滚过去。
  void _sync({bool animate = true}) {
    if (!_hasTiming) return;
    final position = widget.active ? widget.position.value : Duration.zero;
    final i = lyricIndexAt(_timed!, _offset + position);
    if (i == _current) return;
    setState(() => _current = i);
    _scrollTo(i < 0 ? 0 : i, animate: animate);
  }

  void _onTapLine(int i) {
    if (!_hasTiming || !widget.active) return;
    final offset = offsetForTap(_timed![i], widget.position.value);
    setState(() {
      _localOffset = offset;
      _current = i;
    });
    _scrollTo(i);
    widget.onCalibrate?.call(offset);
  }

  /// 让第 [i] 行停在可见区域的第二行。
  void _scrollTo(int i, {bool animate = true}) {
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

  String? get _hint {
    if (!_hasTiming || !widget.active || widget.fullTrack) return null;
    return _calibrated
        ? 'Synced · tap a line to adjust'
        : 'Timing is estimated · tap the line you hear';
  }

  @override
  Widget build(BuildContext context) {
    final tappable = _hasTiming && widget.active;
    final hint = _hint;
    return Column(
      children: [
        Expanded(
          child: ShaderMask(
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
                final current = _hasTiming && i == _current;
                final text = Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: current ? 17 : 15,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                      color: current ? Colors.white : Colors.white70,
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
                if (!tappable) return IgnorePointer(child: text);
                return Semantics(
                  button: true,
                  label: 'Sync lyrics to this line',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onTapLine(i),
                    child: text,
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(
          height: LyricsPanel.hintHeight,
          child: hint == null
              ? null
              : IgnorePointer(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(hint,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                  ),
                ),
        ),
      ],
    );
  }
}
