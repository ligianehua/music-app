import 'package:material_ui/material_ui.dart';

import '../feed/feed_controller.dart';
import '../models/track.dart';
import 'liked_page.dart';
import 'taste_sheet.dart';
import 'track_page.dart';

/// 刷歌主页：全屏竖向翻页，一首歌一屏。
class FeedPage extends StatefulWidget {
  const FeedPage({super.key, required this.controller, this.autoInit = true});

  final FeedController controller;

  /// 测试里可以关掉，手动调用 init。
  final bool autoInit;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _page = PageController();
  int? _animatingTo;

  FeedController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_followController);
    if (widget.autoInit) c.init();
  }

  /// 控制器自己切了歌（自动续播、锁屏按钮、不感兴趣），翻页跟上去。
  ///
  /// 在前台且只差一页时播放翻页动画；在后台或差了好几页（比如锁屏连播了
  /// 几首后解锁）就直接跳过去，否则动画途经的每一页都会被当成用户手势。
  void _followController() {
    if (!_page.hasClients) return;
    final shown = _page.page?.round();
    final target = c.index;
    if (shown == null || shown == target || _animatingTo == target) return;
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (foreground && (target - shown).abs() == 1) {
      _animatingTo = target;
      _page
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _animatingTo = null);
    } else {
      _page.jumpToPage(target);
    }
  }

  Future<void> _openLiked() async {
    final picked = await Navigator.of(context).push<Track>(
      MaterialPageRoute(builder: (_) => LikedPage(controller: c)),
    );
    if (picked != null) await c.goTo(c.insertNext(picked));
  }

  @override
  void dispose() {
    c.removeListener(_followController);
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final Widget body;
          if (c.items.isEmpty) {
            body = _StatusView(
              loading: c.loading || c.error == null,
              error: c.error,
              onRetry: c.retry,
            );
          } else {
            body = PageView.builder(
              controller: _page,
              scrollDirection: Axis.vertical,
              onPageChanged: c.onPageChanged,
              // 末尾多一页：加载中 / 加载失败。
              itemCount: c.items.length + 1,
              itemBuilder: (context, i) {
                if (i >= c.items.length) {
                  return _StatusView(
                    loading: c.loading || c.error == null,
                    error: c.error,
                    onRetry: c.retry,
                  );
                }
                final item = c.items[i];
                return TrackPage(
                  key: ValueKey(item.track.id),
                  item: item,
                  controller: c,
                  active: i == c.index,
                );
              },
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              body,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(
                  onLiked: _openLiked,
                  onTaste: () => showTasteSheet(context, c),
                  likedCount: c.liked.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onLiked,
    required this.onTaste,
    required this.likedCount,
  });

  final VoidCallback onLiked;
  final VoidCallback onTaste;
  final int likedCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
        child: Row(
          children: [
            const Text(
              '刷歌',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
            const SizedBox(width: 8),
            const Text('上滑换一首',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            IconButton(
              tooltip: '我的口味',
              onPressed: onTaste,
              icon: const Icon(Icons.tune_rounded, color: Colors.white),
            ),
            IconButton(
              tooltip: '我喜欢',
              onPressed: onLiked,
              icon: Badge(
                isLabelVisible: likedCount > 0,
                label: Text('$likedCount'),
                backgroundColor: const Color(0xFFFF2D55),
                child: const Icon(Icons.favorite_border_rounded,
                    color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: loading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('正在为你挑歌…', style: TextStyle(color: Colors.white70)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  Text(error ?? '出了点问题',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ),
      ),
    );
  }
}
