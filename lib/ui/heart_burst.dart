import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// 双击位置冒出的红心：弹出、微微旋转、上飘、淡出。
class HeartBurst extends StatefulWidget {
  const HeartBurst({super.key, required this.at, required this.onDone});

  final Offset at;
  final VoidCallback onDone;

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst>
    with SingleTickerProviderStateMixin {
  static const size = 96.0;
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward().whenComplete(widget.onDone);
  late final double _tilt = (Random().nextDouble() - 0.5) * 0.6;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final scale = t < 0.25
            ? Curves.easeOutBack.transform(t / 0.25) * 1.2
            : 1.2 - (t - 0.25) * 0.3;
        final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
        return Positioned(
          left: widget.at.dx - size / 2,
          top: widget.at.dy - size / 2 - t * 60,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0, 1).toDouble(),
              child: Transform.rotate(
                angle: _tilt,
                child: Transform.scale(
                  scale: scale,
                  child: const Icon(
                    Icons.favorite,
                    size: size,
                    color: Color(0xFFFF2D55),
                    shadows: [Shadow(blurRadius: 24, color: Colors.black38)],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
