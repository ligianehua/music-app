import 'package:material_ui/material_ui.dart';

import '../account/auth_service.dart';
import '../app_info.dart';

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

  InputDecoration _field(String label, {Widget? suffix, String? helper}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        helperText: helper,
        helperStyle: const TextStyle(color: Colors.white38),
        helperMaxLines: 2,
        errorMaxLines: 2,
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
      tooltip: _showPassword ? 'Hide password' : 'Show password',
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
                    const Text(appName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    const Text(appTagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _username,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: _field('Username'),
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
                        'Password',
                        suffix: visibility,
                        helper: _register
                            ? 'At least 6 characters, with letters and numbers'
                            : null,
                      ),
                      validator: (v) => _register
                          ? validatePassword(v ?? '')
                          : ((v ?? '').isEmpty ? 'Enter your password.' : null),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirm,
                        obscureText: !_showPassword,
                        style: const TextStyle(color: Colors.white),
                        onFieldSubmitted: (_) => _submit(),
                        decoration: _field('Confirm password'),
                        validator: (v) =>
                            v == _password.text ? null : "Passwords don't match.",
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
                          : Text(_register ? 'Sign up' : 'Log in'),
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
                      child: Text(_register
                          ? 'Already have an account? Log in'
                          : "Don't have an account? Sign up"),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                        'This is a local account. Your account and data stay on this phone.',
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
