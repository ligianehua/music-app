import 'package:material_ui/material_ui.dart';

import '../account/auth_service.dart';

/// 登录 / 注册。
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      if (_register) {
        await widget.auth.register(_username.text, _password.text);
      } else {
        await widget.auth.login(_username.text, _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white10,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final visibility = IconButton(
      tooltip: _showPassword ? '隐藏密码' : '显示密码',
      onPressed: () => setState(() => _showPassword = !_showPassword),
      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
          color: Colors.white54),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('刷歌',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    const Text('像刷短视频一样发现音乐',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _username,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: _field('用户名'),
                      validator: (v) => _register ? validateUsername(v ?? '') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      style: const TextStyle(color: Colors.white),
                      textInputAction:
                          _register ? TextInputAction.next : TextInputAction.done,
                      onFieldSubmitted: (_) => _register ? null : _submit(),
                      autofillHints: [
                        _register ? AutofillHints.newPassword : AutofillHints.password,
                      ],
                      decoration: _field(
                        _register ? '密码（至少 6 位，含字母和数字）' : '密码',
                        suffix: visibility,
                      ),
                      validator: (v) => _register
                          ? validatePassword(v ?? '')
                          : ((v ?? '').isEmpty ? '请输入密码' : null),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirm,
                        obscureText: !_showPassword,
                        style: const TextStyle(color: Colors.white),
                        onFieldSubmitted: (_) => _submit(),
                        decoration: _field('再输一次密码'),
                        validator: (v) =>
                            v == _password.text ? null : '两次输入的密码不一样',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF6B6B))),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? '注册' : '登录'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                                // 清掉表单的错误提示，但保留已经输入的内容。
                                final name = _username.text;
                                final pw = _password.text;
                                _form.currentState?.reset();
                                _username.text = name;
                                _password.text = pw;
                                _confirm.clear();
                              }),
                      child: Text(_register ? '已有账号？去登录' : '没有账号？注册一个'),
                    ),
                    const SizedBox(height: 16),
                    const Text('当前是本机账号：账号和数据只保存在这台手机上',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
