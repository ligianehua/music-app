import 'package:material_ui/material_ui.dart';

import '../account/auth_service.dart';
import '../app_info.dart';
import '../feed/feed_controller.dart';
import '../models/track.dart';
import 'me_page.dart';
import 'search_page.dart';
import 'taste_sheet.dart';
import 'track_page.dart';

/// 刷歌主页：全屏竖向翻页，一首歌一屏。
class FeedPage extends StatefulWidget {
  const FeedPage({
    super.key,
    required this.controller,
    required this.auth,
    this.autoInit = true,
  });

  final FeedController controller;
  final AuthService auth;

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

  Future<void> _openMe() async {
    final picked = await Navigator.of(context).push<PickedTrack>(
      MaterialPageRoute(builder: (_) => MePage(controller: c, auth: widget.auth)),
    );
    if (picked != null) await c.playNow(picked.track, reason: picked.reason);
  }

  Future<void> _openSearch() async {
    final picked = await Navigator.of(context).push<Track>(
      MaterialPageRoute(builder: (_) => SearchPage(controller: c)),
    );
    if (picked != null) await c.playNow(picked, reason: 'From your search');
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
              loading: c.loading,
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
                    loading: c.loading,
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
                  onSearch: _openSearch,
                  onMe: _openMe,
                  onTaste: () => showTasteSheet(context, c),
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
    required this.onSearch,
    required this.onMe,
    required this.onTaste,
  });

  final VoidCallback onSearch;
  final VoidCallback onMe;
  final VoidCallback onTaste;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
        child: Row(
          children: [
            // 小屏或字体放大时，名称自动缩小，给右侧按钮留位置。
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  appName,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
              ),
            ),
            _TopIcon(
              tooltip: 'Search',
              onPressed: onSearch,
              icon: Icons.search_rounded,
            ),
            _TopIcon(
              tooltip: 'Your taste',
              onPressed: onTaste,
              icon: Icons.tune_rounded,
            ),
            _TopIcon(
              tooltip: 'Profile',
              onPressed: onMe,
              icon: Icons.person_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏图标按钮：点击区域 44x44，比默认的 48 紧凑一点。
class _TopIcon extends StatelessWidget {
  const _TopIcon({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white,
            shadows: const [Shadow(blurRadius: 8, color: Colors.black54)]),
      );
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
                  Text('Finding songs for you…',
                      style: TextStyle(color: Colors.white70)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(error ?? 'No more songs right now.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
      ),
    );
  }
}
