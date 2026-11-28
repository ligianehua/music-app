import 'package:material_ui/material_ui.dart';

import '../feed/feed_controller.dart';
import '../models/track.dart';
import '../social/comment.dart';

/// 评论弹层。
Future<void> showCommentsSheet(
    BuildContext context, FeedController c, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => CommentsSheet(controller: c, track: track),
  );
}

/// 「刚刚」「5 分钟前」「3 天前」，超过一个月显示日期。
String relativeTime(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.controller, required this.track});
  final FeedController controller;
  final Track track;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _input = TextEditingController();
  late Future<List<Comment>> _comments =
      widget.controller.loadComments(widget.track);
  bool _sending = false;

  FeedController get c => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || _input.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await c.addComment(widget.track, _input.text);
      _input.clear();
      setState(() => _comments = c.loadComments(widget.track));
    } on ArgumentError catch (e) {
      _toast('${e.message}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDelete(Comment comment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条评论？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await c.deleteComment(comment);
    setState(() => _comments = c.loadComments(widget.track));
  }

  void _toast(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final n = c.commentCount(widget.track);
                return Text(n == null ? '评论' : '$n 条评论',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white));
              },
            ),
            const SizedBox(height: 4),
            const Text('评论保存在这台手机上，同一台手机的账号互相可见',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
            const Divider(color: Colors.white12, height: 24),
            Expanded(
              child: FutureBuilder<List<Comment>>(
                future: _comments,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return const Center(
                      child: Text('还没有评论，来说第一句',
                          style: TextStyle(color: Colors.white38)),
                    );
                  }
                  final now = DateTime.now();
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, i) {
                      final cm = list[i];
                      final mine = cm.userId == c.user.id;
                      return GestureDetector(
                        onLongPress: mine ? () => _confirmDelete(cm) : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white12,
                              child: Text(cm.username.characters.first,
                                  style: const TextStyle(color: Colors.white)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${cm.username}${mine ? '（我）' : ''} · ${relativeTime(cm.createdAt, now)}',
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(cm.text,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: maxCommentLength,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '以 ${c.user.username} 的身份说点什么…',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _submit,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      tooltip: '发送',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
