import 'support/memory_session_store.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/email_login_page.dart';
import 'package:weaver/features/auth/google_auth.dart';

class FakeGoogle implements GoogleAuthClient {
  @override bool get configured => false;
  @override Stream<GoogleIdentity?> get changes => const Stream.empty();
  @override Future<void> initialize() async {}
  @override Future<void> signIn() async {}
  @override Future<void> signOut() async {}
  @override Future<void> dispose() async {}
}
void main() {
  test('HTML server errors retain HTTP status instead of reporting a connection failure', () async {
    final api=EmailAuthApi(store:MemorySessionStore(),client:MockClient((_)async=>http.Response('<html>Internal server error</html>',500)));
    await expectLater(api.post('session/native/workspace/save',{}),throwsA(isA<EmailAuthFailure>().having((e)=>e.status,'status',500).having((e)=>e.message,'message',contains('서버에서 요청을 처리하지 못했습니다'))));api.dispose();
  });
  test('Invalid successful responses are distinguished from network failures', () async {
    final api=EmailAuthApi(store:MemorySessionStore(),client:MockClient((_)async=>http.Response('<html>unexpected</html>',200)));
    await expectLater(api.post('session/native/workspace/read',{}),throwsA(isA<EmailAuthFailure>().having((e)=>e.message,'message',contains('서버 응답 형식'))));api.dispose();
  });
  test('Email session is not restored through insecure Google test marker', () async {
    SharedPreferences.setMockInitialValues({GoogleAuthController.rememberedAccountKey: jsonEncode({'id':'old','email':'old@example.com'})});
    final prefs = await SharedPreferences.getInstance();
    final requests = <http.Request>[];
    final api = EmailAuthApi(store: MemorySessionStore(), client: MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(r.url.path.endsWith('login') ? {'id':'123','email':'person@example.com','refreshToken':'secret','accessToken':'access','expiresIn':43200} : {'message':'ok'}),200);
    }));
    final auth = GoogleAuthController(FakeGoogle(), preferences:prefs,emailApi:api);
    await auth.signInWithEmail('person@example.com','long-password');
    expect(auth.identity?.id,'email:123');
    expect(prefs.getString(GoogleAuthController.rememberedAccountKey),isNull);
    expect(auth.identity?.idToken,isNull);
    await auth.signOut();
    expect(jsonDecode(requests.last.body)['refreshToken'],'secret');
    expect(auth.identity,isNull);auth.dispose();
  });
  testWidgets('Signup rejects mismatched passwords before contacting server', (tester) async {
    var calls=0;
    final auth=GoogleAuthController(FakeGoogle(),emailApi:EmailAuthApi(store: MemorySessionStore(), client:MockClient((_) async {calls++;return http.Response('{}',200);})));
    await tester.pumpWidget(MaterialApp(home:EmailLoginPage(auth:auth)));
    await tester.tap(find.text('계정이 없으신가요? Sign up'));await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0),'테스트 사용자');
    await tester.enterText(find.byType(TextFormField).at(1),'person@example.com');
    await tester.enterText(find.byType(TextFormField).at(2),'long-password');
    await tester.enterText(find.byType(TextFormField).at(3),'different-password');
    await tester.ensureVisible(find.text('Sign up · 인증메일 받기'));
    await tester.tap(find.text('Sign up · 인증메일 받기'));await tester.pump();
    expect(find.text('비밀번호가 일치하지 않습니다.'),findsOneWidget);expect(calls,0);
    await tester.pumpWidget(const SizedBox());auth.dispose();
  });
  testWidgets('Verification requires explicit button and does not log in automatically', (tester) async {
    var calls=0;
    final auth=GoogleAuthController(FakeGoogle(),emailApi:EmailAuthApi(store: MemorySessionStore(), client:MockClient((r) async {
      calls++;expect(jsonDecode(r.body)['token'],'test-token');return http.Response(jsonEncode({'message':'인증 완료'}),200,headers:{'content-type':'application/json; charset=utf-8'});
    })));
    await tester.pumpWidget(MaterialApp(home:EmailLoginPage(auth:auth,verificationToken:'test-token',onVerified:(){})));
    expect(calls,0);await tester.tap(find.widgetWithText(FilledButton,'이메일 인증'));await tester.pumpAndSettle();
    expect(calls,1);expect(find.text('로그인 화면으로'),findsOneWidget);expect(auth.identity,isNull);
    await tester.pumpWidget(const SizedBox());auth.dispose();
  });
}
