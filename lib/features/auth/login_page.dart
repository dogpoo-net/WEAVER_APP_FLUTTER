import 'package:flutter/material.dart';
import 'google_auth.dart';
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
        if (auth.busy) const Padding(padding: EdgeInsets.only(top: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        if (!auth.client.configured) const Padding(padding: EdgeInsets.only(top: 16), child: Text('Google 로그인 설정을 준비 중입니다.', textAlign: TextAlign.center)),
        if (auth.error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(auth.error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    )),
  )));
}
