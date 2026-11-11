import 'dart:convert';
import 'package:flutter/material.dart';
import 'email_auth.dart';
import 'google_auth.dart';

class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key, required this.auth, this.verificationToken, this.onVerified});
  final GoogleAuthController auth;
  final String? verificationToken;
  final VoidCallback? onVerified;
  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController(), _password = TextEditingController(), _confirmation = TextEditingController();
  bool _signup = false, _busy = false, _verified = false;
  String? _message, _error;
  @override
  void dispose() { _name.dispose(); _email.dispose(); _password.dispose(); _confirmation.dispose(); super.dispose(); }
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; _error = null; });
    try { await action(); }
    on EmailAuthFailure catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = '요청을 처리하지 못했습니다. 다시 시도해주세요.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      if (_signup) {
        final data = await widget.auth.emailApi.post('signup', {'name': _name.text.trim(), 'email': _email.text.trim(),
          'password': _password.text, 'passwordConfirmation': _confirmation.text});
        if (mounted) setState(() { _message = data['message'] as String; _password.clear(); _confirmation.clear(); _signup = false; });
      } else {
        await widget.auth.signInWithEmail(_email.text.trim(), _password.text);
      }
    });
  }
  String? _validateEmail(String? value) => value == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? '올바른 이메일 주소를 입력해주세요.' : null;
  @override
  Widget build(BuildContext context) {
    final verification = widget.verificationToken != null;
    return Scaffold(appBar: AppBar(title: Text(verification ? '이메일 인증' : _signup ? 'Sign up · 회원가입' : 'Sign in · 이메일 로그인')),
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: Form(key: _form,
          child: AutofillGroup(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (verification) ...[
              const Text('아래 버튼을 눌러 이메일 인증을 완료하세요. 인증 링크는 30분 동안 유효합니다.'),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _verified ? widget.onVerified : () => _run(() async {
                final data = await widget.auth.emailApi.post('verify', {'token': widget.verificationToken!});
                if (mounted) setState(() { _verified = true; _message = data['message'] as String; });
              }), child: Text(_verified ? '로그인 화면으로' : '이메일 인증')),
              if (!_verified) TextButton(onPressed: _busy ? null : widget.onVerified, child: const Text('로그인 / 인증메일 다시 받기')),
            ] else ...[
              if (_signup) ...[
                TextFormField(controller: _name, enabled: !_busy, autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: '이름'),
                  validator: (v) => v == null || v.trim().isEmpty || v.trim().runes.length > 80 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(v)
                    ? '이름을 1~80자로 입력해주세요.' : null),
                const SizedBox(height: 16),
              ],
              TextFormField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username, AutofillHints.email], autocorrect: false,
                decoration: const InputDecoration(labelText: '이메일'), validator: _validateEmail),
              const SizedBox(height: 16),
              TextFormField(controller: _password, enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false,
                autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                decoration: const InputDecoration(labelText: '비밀번호', helperText: '10자 이상 · 최대 72바이트'),
                validator: (v) => v == null || v.length < 10 || utf8.encode(v).length > 72 ? '비밀번호 길이를 확인해주세요.' : null,
                onFieldSubmitted: (_) { if (!_signup) _submit(); }),
              if (_signup) ...[
                const SizedBox(height: 16),
                TextFormField(controller: _confirmation, enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword], decoration: const InputDecoration(labelText: '비밀번호 확인'),
                  validator: (v) => v != _password.text ? '비밀번호가 일치하지 않습니다.' : null, onFieldSubmitted: (_) => _submit()),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _submit, child: Text(_signup ? 'Sign up · 인증메일 받기' : 'Sign in')),
              TextButton(onPressed: _busy ? null : () => setState(() { _signup = !_signup; _message = null; _error = null; _password.clear(); _confirmation.clear(); }),
                child: Text(_signup ? '이미 계정이 있나요? Sign in' : '계정이 없으신가요? Sign up')),
              TextButton(onPressed: _busy ? null : () {
                if (_validateEmail(_email.text) != null) { setState(() => _error = '먼저 이메일 주소를 입력해주세요.'); return; }
                _run(() async {
                  final data = await widget.auth.emailApi.post('resend', {'email': _email.text.trim()});
                  if (mounted) setState(() => _message = data['message'] as String);
                });
              }, child: const Text('인증메일 다시 받기')),
            ],
            if (_busy) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, semanticsLabel: _message, textAlign: TextAlign.center)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center)),
          ])),
        )),
      ))),
    );
  }
}
