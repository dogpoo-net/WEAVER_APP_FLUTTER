import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'google_auth_test.dart' show FakeGoogleClient;
import 'support/memory_session_store.dart';
class PopupGoogleClient extends FakeGoogleClient {
 @override Future<void> signIn() async { events.add(const GoogleIdentity(id:'',email:'',idToken:null,accessToken:'google-popup-token')); }
}
void main(){
 testWidgets('custom Google button exchanges OAuth token for server session only', (tester) async {
  final store=MemorySessionStore();var exchanges=0;
  final api=EmailAuthApi(store:store,client:MockClient((request)async{
   if(request.url.path.endsWith('/google')){
    exchanges++;expect(jsonDecode(request.body),{'googleAccessToken':'google-popup-token'});
   }
   return http.Response(jsonEncode({'id':'server-account','email':'test@example.com','name':'Test','expiresIn':1800,'refreshToken':'server-refresh','accessToken':'server-access'}),200);
  }));
  await tester.pumpWidget(MyApp(emailApi:api,authClient:PopupGoogleClient()));await tester.pumpAndSettle();
  final button=find.ancestor(of:find.text('Google로 로그인'),matching:find.byType(OutlinedButton));expect(button,findsOneWidget);
  await tester.tap(button);await tester.pumpAndSettle();
  expect(exchanges,1);expect(find.byType(InboxPage),findsOneWidget);expect(store.value,isNot(contains('google-popup-token')));
  await tester.pumpWidget(const SizedBox());
 });
}
