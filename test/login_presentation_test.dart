import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/email_login_page.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/kakao_auth.dart';
import 'package:weaver/features/auth/login_page.dart';
import 'package:weaver/features/auth/login_provider_button.dart';
import 'support/memory_session_store.dart';
class NoGoogle implements GoogleAuthClient {
 @override bool get configured=>false;
 @override Stream<GoogleIdentity?> get changes=>const Stream.empty();
 @override Future<void> initialize() async {}
 @override Future<void> signIn() async {}
 @override Future<void> signOut() async {}
 @override Future<void> dispose() async {}
}
class FakeKakao implements KakaoAuthClient {
 @override bool get configured=>true;
 @override Future<String?> accessToken() async=>'temporary-kakao-token';
}
void main(){
 testWidgets('Provider buttons share dimensions and Apple is absent', (tester) async {
  final auth=GoogleAuthController(NoGoogle(),emailApi:EmailAuthApi(store:MemorySessionStore()),kakaoClient:FakeKakao());
  await tester.pumpWidget(MaterialApp(home:LoginPage(auth:auth)));
  expect(find.textContaining('Apple'),findsNothing);
  expect(find.byType(LoginProviderButton),findsNWidgets(6));
  for(final button in find.byType(LoginProviderButton).evaluate()){
   expect(tester.getSize(find.byWidget(button.widget)),const Size(320,40));
  }
  await tester.pumpWidget(const SizedBox());auth.dispose();
 });
 testWidgets('Signup requires and sends a trimmed name', (tester) async {
  Map<String,dynamic>? sent;
  final auth=GoogleAuthController(NoGoogle(),emailApi:EmailAuthApi(store:MemorySessionStore(),client:MockClient((r) async {
   sent=jsonDecode(r.body);return http.Response(jsonEncode({'message':'메일 발송'}),200,headers:{'content-type':'application/json; charset=utf-8'});
  })));
  await tester.pumpWidget(MaterialApp(home:EmailLoginPage(auth:auth)));
  await tester.tap(find.text('계정이 없나요? Sign up'));await tester.pump();
  await tester.enterText(find.byType(TextFormField).at(1),'name@example.com');
  await tester.enterText(find.byType(TextFormField).at(2),'long-password');
  await tester.enterText(find.byType(TextFormField).at(3),'long-password');
  await tester.ensureVisible(find.text('Sign up · 인증메일 받기'));
  await tester.tap(find.text('Sign up · 인증메일 받기'));await tester.pump();
  expect(sent,isNull);expect(find.text('이름을 1~80자로 입력해주세요.'),findsOneWidget);
  await tester.enterText(find.byType(TextFormField).at(0),'  김민수  ');
  await tester.ensureVisible(find.text('Sign up · 인증메일 받기'));
  await tester.tap(find.text('Sign up · 인증메일 받기'));await tester.pumpAndSettle();
  expect(sent?['name'],'김민수');await tester.pumpWidget(const SizedBox());auth.dispose();
 });
 test('Kakao SDK token is exchanged for a server session, never persisted', () async {
  final store=MemorySessionStore();
  final auth=GoogleAuthController(NoGoogle(),kakaoClient:FakeKakao(),emailApi:EmailAuthApi(store:store,client:MockClient((r) async {
   expect(r.url.path,endsWith('/native/kakao'));expect(jsonDecode(r.body)['kakaoToken'],'temporary-kakao-token');
   return http.Response(jsonEncode({'id':'account','email':'person@example.com','name':'김민수','accessToken':'access','refreshToken':'refresh','expiresIn':1800}),200,headers:{'content-type':'application/json; charset=utf-8'});
  })));
  await auth.signInWithKakao();expect(auth.identity?.displayName,'김민수');expect(auth.canUseCloud,isTrue);
  expect(store.value,isNot(contains('temporary-kakao-token')));expect(store.value,contains('refresh'));auth.dispose();
 });
}
