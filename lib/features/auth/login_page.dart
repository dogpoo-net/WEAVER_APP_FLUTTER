import 'package:flutter/material.dart';
import 'google_auth.dart';
import 'email_login_page.dart';
import 'google_button.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.auth});
  final GoogleAuthController auth;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('WEAVER', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 5)),
        const SizedBox(height: 12),
        const Text('생각을 기록하고 연결하세요.'),
        const SizedBox(height: 36),
        if (auth.ready) googleSignInButton(onPressed: auth.busy ? null : auth.signIn)
        else const OutlinedButton(onPressed: null, child: Text('Google로 로그인')),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmailLoginPage(auth: auth))), child: const Text('이메일로 로그인 / 회원가입')),
        const SizedBox(height: 12),
        const OutlinedButton(onPressed: null, child: Text('Apple 로그인 · 준비 중')),
        const OutlinedButton(onPressed: null, child: Text('카카오 로그인 · 준비 중')),
        const OutlinedButton(onPressed: null, child: Text('네이버 로그인 · 준비 중')),
        const SizedBox(height: 16),
        TextButton(onPressed: auth.useGuest, child: const Text('비회원으로 사용하기')),
        const Text('비회원은 이 기기에만 저장됩니다. 로그인 후 클라우드에 올릴 수 있습니다.', textAlign: TextAlign.center),
        if (auth.busy) const Padding(padding: EdgeInsets.only(top: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        if (!auth.client.configured) const Padding(padding: EdgeInsets.only(top: 16), child: Text('Google 로그인 설정을 준비 중입니다.', textAlign: TextAlign.center)),
        if (auth.error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(auth.error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    )),
  )));
}
