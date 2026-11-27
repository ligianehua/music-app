import 'package:material_ui/material_ui.dart';

import '../feed/feed_controller.dart';
import '../models/track.dart';

/// 「心得」：纯前端 Demo 没有服务器，评论只存在本机，界面上明确告诉用户。
Future<void> showNotesSheet(
    BuildContext context, FeedController c, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _NotesSheet(controller: c, track: track),
  );
}

class _NotesSheet extends StatefulWidget {
  const _NotesSheet({required this.controller, required this.track});
  final FeedController controller;
  final Track track;

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await widget.controller.addNote(widget.track, _input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text('《${widget.track.title}》的听歌心得',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 4),
            const Text('只保存在这台设备上，不会上传',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
            const Divider(color: Colors.white12, height: 24),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final notes = widget.controller.notesFor(widget.track);
                  if (notes.isEmpty) {
                    return const Center(
                      child: Text('还没有心得，写下第一句吧',
                          style: TextStyle(color: Colors.white38)),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => Text(notes[i],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, height: 1.4)),
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
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: '这首歌让你想到了什么？',
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
                      onPressed: _submit,
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
