import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/profile_page.dart';
import 'package:weaver/features/inbox/thought_settings.dart';

import 'support/memory_session_store.dart';
import 'google_auth_test.dart' show FakeGoogleClient;

void main() {
  testWidgets(
    'profile edits name and keeps the same account; settings has no social links',
    (tester) async {
      var name = 'Original';
      final api = EmailAuthApi(
        store: MemorySessionStore(isWeb: true),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/profile/name')) {
            name = jsonDecode(r.body)['name'] as String;
            return http.Response('{}', 200);
          }
          if (r.url.path.endsWith('/profile/read')) {
            return http.Response(
              jsonEncode({
                'name': name,
                'email': 'a@example.com',
                'providers': ['github'],
                'emailEnabled': true,
                'defaultFace': 3,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'a',
              'email': 'a@example.com',
              'name': name,
              'expiresIn': 1800,
            }),
            200,
          );
        }),
      );
      final auth = GoogleAuthController(
        FakeGoogleClient(configured: false),
        emailApi: api,
      );
      await auth.signInWithEmail('a@example.com', 'test-password');
      await tester.pumpWidget(
        GoogleAuthScope(
          controller: auth,
          child: MaterialApp(home: ProfilePage(auth: auth)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('비밀번호 변경'), findsOneWidget);
      final fallback =
          tester.widget<Image>(find.byType(Image).first).image as AssetImage;
      expect(fallback.assetName, 'assets/branding/profile/face_3.png');
      await tester.tap(find.byTooltip('이름 변경'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Changed');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(auth.identity!.id, 'email:a');
      expect(find.text('Changed'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('profile-withdrawal')), 250);
      final withdrawal=tester.widget<ListTile>(find.byKey(const ValueKey('profile-withdrawal')));
      expect(withdrawal.leading,isNull);
      expect((withdrawal.title as Text).style?.color,const Color(0xFFD64550));
      await tester.pumpWidget(
        GoogleAuthScope(
          controller: auth,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showThoughtSettings(context, null),
                  child: const Text('settings'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();
      expect(find.text('GitHub 계정 연결'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Changed')).dy,
        lessThan(tester.getTopLeft(find.text('워크스페이스')).dy),
      );
      expect(
        tester.widget<Text>(find.text('Changed')).textAlign,
        TextAlign.right,
      );
      expect(
        tester.getTopLeft(find.text('동기화 관리')).dy,
        lessThan(tester.getTopLeft(find.text('닫힌 생각 숨기기')).dy),
      );
      expect(tester.widget<Text>(find.text('데이터 초기화')).style?.color, Colors.white);
      for (final label in ['로그아웃', '모든 기기에서 로그아웃']) {
        expect(
          tester.widget<Text>(find.text(label)).style?.color,
          isNull,
        );
      }
      final resetTile=tester.widget<ListTile>(find.ancestor(of:find.text('데이터 초기화'),matching:find.byType(ListTile)));
      expect((resetTile.leading as Icon).icon,Icons.refresh);
      expect(find.text('회원탈퇴'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      auth.dispose();
    },
  );
  testWidgets('missing profile and session names use email prefix', (tester) async {
    final api=EmailAuthApi(store:MemorySessionStore(isWeb:true),client:MockClient((r)async{
      if(r.url.path.endsWith('/profile/read')) return http.Response(jsonEncode({'name':'','email':'person@example.com','providers':[],'defaultFace':0}),200);
      return http.Response(jsonEncode({'id':'a','email':'person@example.com','name':'','expiresIn':1800}),200);
    }));
    final auth=GoogleAuthController(FakeGoogleClient(configured:false),emailApi:api);
    await auth.signInWithEmail('person@example.com','test-password');await auth.loadProfile();
    await tester.pumpWidget(GoogleAuthScope(controller:auth,child:MaterialApp(home:ProfilePage(auth:auth))));await tester.pumpAndSettle();
    expect(find.text('person'),findsOneWidget);expect(auth.identity?.displayName,'person');
    await tester.pumpWidget(const SizedBox());auth.dispose();
  });
  testWidgets('profile photo menu applies a server-selected default', (tester) async {
    var face=1,calls=0;
    final api=EmailAuthApi(store:MemorySessionStore(isWeb:true),client:MockClient((r)async{
      if(r.url.path.endsWith('/photo/default')){calls++;face=4;return http.Response('{}',200);}
      if(r.url.path.endsWith('/profile/read'))return http.Response(jsonEncode({'name':'Name','email':'a@example.com','providers':[],'defaultFace':face}),200);
      return http.Response(jsonEncode({'id':'a','email':'a@example.com','name':'Name','expiresIn':1800}),200);
    }));
    final auth=GoogleAuthController(FakeGoogleClient(configured:false),emailApi:api);
    await auth.signInWithEmail('a@example.com','test-password');
    await tester.pumpWidget(GoogleAuthScope(controller:auth,child:MaterialApp(home:ProfilePage(auth:auth))));await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('프로필 사진 변경'));await tester.pumpAndSettle();
    expect(find.text('사진 변경'),findsOneWidget);expect(calls,0);
    await tester.tap(find.text('기본 사진 적용'));await tester.pumpAndSettle();
    expect(calls,1);expect(auth.profile?['defaultFace'],4);
    expect((tester.widget<Image>(find.byType(Image).first).image as AssetImage).assetName,'assets/branding/profile/face_4.png');
    await tester.pumpWidget(const SizedBox());auth.dispose();
  });
  for (final initial in ['kakao', 'email']) {
    testWidgets('unlink controls preserve initial signup method: $initial', (tester) async {
      final providers = ['google', 'kakao'];var unlinks=0;
      final api = EmailAuthApi(store: MemorySessionStore(isWeb:true), client:MockClient((r) async {
        if(r.url.path.endsWith('/profile/read')) return http.Response(jsonEncode({'name':'Name','email':'same@example.com','providers':providers,'signupProvider':initial,'emailEnabled':initial=='email','defaultFace':0}),200);
        if(r.url.path.endsWith('/profile/social/unlink')) {unlinks++;providers.remove(jsonDecode(r.body)['provider']);return http.Response('{}',200);}
        return http.Response(jsonEncode({'id':'a','email':'same@example.com','name':'Name','expiresIn':1800}),200);
      }));
      final auth=GoogleAuthController(FakeGoogleClient(configured:false),emailApi:api);
      await auth.signInWithEmail('same@example.com','test-password');
      await tester.pumpWidget(GoogleAuthScope(controller:auth,child:MaterialApp(home:ProfilePage(auth:auth))));await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('unlink-google')),150);
      expect(find.byKey(const ValueKey('unlink-google')),findsOneWidget);
      if(initial=='email') { await tester.scrollUntilVisible(find.byKey(const ValueKey('unlink-kakao')),150);expect(find.byKey(const ValueKey('unlink-kakao')),findsOneWidget);await tester.ensureVisible(find.byKey(const ValueKey('unlink-google')));await tester.pumpAndSettle(); }
      else {expect(find.byKey(const ValueKey('unlink-kakao')),findsNothing);}
      await tester.tap(find.byKey(const ValueKey('unlink-google')));await tester.pumpAndSettle();
      expect(unlinks,0);await tester.tap(find.widgetWithText(TextButton,'취소'));await tester.pumpAndSettle();expect(unlinks,0);
      await tester.tap(find.byKey(const ValueKey('unlink-google')));await tester.pumpAndSettle();
      await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.widgetWithText(TextButton,'연결 해제')));await tester.pumpAndSettle();
      expect(unlinks,1);expect(providers, isNot(contains('google')));
      await tester.pumpWidget(const SizedBox());auth.dispose();
    });
  }
  test('Google linking sends a linking request without replacing the current session identity', () async {
    final requests = <String>[];
    final client = FakeGoogleClient();
    final api = EmailAuthApi(
      store: MemorySessionStore(isWeb: true),
      client: MockClient((r) async {
        requests.add(r.url.path);
        if (r.url.path.endsWith('/profile/read')) {
          return http.Response(
            '{"name":"Current","email":"a@example.com","providers":[],"emailEnabled":true}',
            200,
          );
        }
        return http.Response(
          '{"id":"a","email":"a@example.com","expiresIn":1800}',
          200,
        );
      }),
    );
    final auth = GoogleAuthController(client, emailApi: api);
    await auth.signInWithEmail('a@example.com', 'password');
    await auth.prepareGoogleLink();
    await auth.startGoogleLink();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests.where((p) => p.endsWith('/google/link')), hasLength(1));
    expect(requests.where((p) => p.endsWith('/google')), isEmpty);
    expect(auth.identity!.id, 'email:a');
    auth.dispose();
  });
}
