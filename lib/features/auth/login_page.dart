import 'package:flutter/material.dart';
import 'google_auth.dart';
import 'email_login_page.dart';
import 'google_button.dart';
import 'login_provider_button.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.auth,this.invitationPending=false});
  final GoogleAuthController auth;
  final bool invitationPending;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: loginButtonMaxWidth),
      child: LayoutBuilder(builder: (context, constraints) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('WEAVER', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 5)),
        const SizedBox(height: 12),
        const Text('생각을 기록하고 연결하세요.'),
        if(invitationPending)const Padding(padding:EdgeInsets.only(top:12),child:Text('초대받은 이메일 계정으로 로그인하면 워크스페이스 초대를 수락할 수 있습니다.',textAlign:TextAlign.center)),
        const SizedBox(height: 36),
        LoginProviderButton(label: '이메일로 로그인 / 회원가입', icon: Icons.mail_outline,
          onPressed: auth.busy ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmailLoginPage(auth: auth)))),
        const SizedBox(height: 12),
        if (auth.ready) googleSignInButton(width: constraints.maxWidth, onPressed: auth.busy ? null : auth.signIn)
        else const LoginProviderButton(label: 'Google로 로그인', symbolAsset: 'assets/branding/social/google.png'),
        const SizedBox(height: 12),
        LoginProviderButton(label: 'GitHub로 로그인', symbolAsset: 'assets/branding/social/github.png', onPressed: auth.busy ? null : () => auth.signInWithBrowser('github')),
        const SizedBox(height: 12),
        LoginProviderButton(label: 'GitLab으로 로그인', symbolAsset: 'assets/branding/social/gitlab.png', onPressed: auth.busy ? null : () => auth.signInWithBrowser('gitlab')),
        const SizedBox(height: 12),
        LoginProviderButton(label: auth.kakaoClient.configured ? '카카오로 로그인' : '카카오 로그인 · 앱 미지원', symbolAsset: 'assets/branding/social/kakao.png',
          onPressed: auth.kakaoClient.configured && !auth.busy ? auth.signInWithKakao : null),
        const SizedBox(height: 12),
        LoginProviderButton(label: '네이버로 로그인', symbolAsset: 'assets/branding/social/naver.png', onPressed: auth.busy ? null : () => auth.signInWithBrowser('naver')),
        const SizedBox(height: 20),
        TextButton(onPressed: auth.signingInWithBrowser ? null : auth.useGuest, child: const Text('비회원으로 사용하기')),
        Text('비회원은 이 기기에만 저장됩니다. 로그인 후 기기 간 동기화가 가능합니다.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        if (auth.signingInWithBrowser) TextButton(onPressed: auth.cancelBrowserSignIn, child: const Text('로그인 취소')),
        if (auth.busy) const Padding(padding: EdgeInsets.only(top: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        if (!auth.client.configured) const Padding(padding: EdgeInsets.only(top: 16), child: Text('Google 로그인 설정을 준비 중입니다.', textAlign: TextAlign.center)),
        if (auth.emailRestorePending) TextButton(onPressed: auth.resumeEmailSession, child: const Text('로그인 상태 다시 확인')),
        if (auth.error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(auth.error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ])),
    )),
  )));
}
