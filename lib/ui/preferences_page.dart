import 'package:material_ui/material_ui.dart';

import '../account/user.dart';
import '../recommend/preference_options.dart';

/// 听歌偏好：语言、风格、歌手、网红热歌。注册后必经一次，之后可在「我的」里改。
///
/// 作为路由使用时，保存会返回 [UserPreferences]；作为页面嵌入时通过 [onSubmit] 回调。
class PreferencesPage extends StatefulWidget {
  const PreferencesPage({
    super.key,
    this.initial = const UserPreferences(),
    this.title = '选几个你喜欢的',
    this.submitLabel = '开始刷歌',
    this.onSubmit,
    this.onboarding = false,
  });

  final UserPreferences initial;
  final String title;
  final String submitLabel;
  final Future<void> Function(UserPreferences)? onSubmit;

  /// 注册后的首次设置：不能返回，可以跳过。
  final bool onboarding;

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  late final Set<String> _languages = {...widget.initial.languages};
  late final Set<String> _genres = {...widget.initial.genres};
  late final Set<String> _artists = {...widget.initial.artists};
  late bool _viral = widget.initial.viral;
  final _customArtist = TextEditingController();
  bool _saving = false;

  UserPreferences get _value => UserPreferences(
        languages: _languages,
        genres: _genres,
        artists: _artists,
        viral: _viral,
      );

  @override
  void dispose() {
    _customArtist.dispose();
    super.dispose();
  }

  Future<void> _submit(UserPreferences prefs) async {
    setState(() => _saving = true);
    try {
      if (widget.onSubmit != null) {
        await widget.onSubmit!(prefs);
      } else {
        Navigator.of(context).pop(prefs);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addCustomArtist() {
    final name = _customArtist.text.trim();
    if (name.isEmpty) return;
    setState(() => _artists.add(name));
    _customArtist.clear();
  }

  @override
  Widget build(BuildContext context) {
    final artistChoices = {...artistOptionsFor(_languages), ..._artists}.toList();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.onboarding,
        title: Text(widget.title),
        actions: [
          if (widget.onboarding)
            TextButton(
              onPressed: _saving
                  ? null
                  // 跳过等于「什么语言都推」，以后在「我的」里随时可以改。
                  : () => _submit(UserPreferences(languages: {...languageOptions})),
              child: const Text('跳过，什么都推'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text('选得越多，第一批推荐越准。之后你刷歌、点赞、搜索，推荐还会继续学。',
              style: TextStyle(color: Colors.white54)),
          _Section(
            title: '语言',
            child: _Chips(
              options: languageOptions,
              selected: _languages,
              onToggle: (v) => setState(() => _toggle(_languages, v)),
            ),
          ),
          _Section(
            title: '风格',
            child: _Chips(
              options: genreOptions,
              selected: _genres,
              onToggle: (v) => setState(() => _toggle(_genres, v)),
            ),
          ),
          _Section(
            title: '歌手',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Chips(
                  options: artistChoices,
                  selected: _artists,
                  onToggle: (v) => setState(() => _toggle(_artists, v)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customArtist,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (_) => _addCustomArtist(),
                        decoration: const InputDecoration(
                          hintText: '没有你喜欢的？输入歌手名添加',
                          hintStyle: TextStyle(color: Colors.white38),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '添加歌手',
                      onPressed: _addCustomArtist,
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _Section(
            title: '网红热歌',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _viral,
              onChanged: (v) => setState(() => _viral = v),
              title: const Text('多推正在流行的歌',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('来自 Apple Music 港台区的热门榜和网络歌手',
                  style: TextStyle(color: Colors.white54)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: _saving || _value.isEmpty ? null : () => _submit(_value),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: Text(_value.isEmpty ? '至少选一项' : widget.submitLabel),
          ),
        ),
      ),
    );
  }

  static void _toggle(Set<String> set, String v) {
    if (!set.remove(v)) set.add(v);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

class _Chips extends StatelessWidget {
  const _Chips({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            FilterChip(
              label: Text(o),
              selected: selected.contains(o),
              onSelected: (_) => onToggle(o),
            ),
        ],
      );
}
