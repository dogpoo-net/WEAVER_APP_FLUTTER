import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/account_cache.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/withdrawal_page.dart';
import 'google_auth_test.dart' show FakeGoogleClient;
import 'support/memory_session_store.dart';
class WithdrawalAuth extends GoogleAuthController {
 WithdrawalAuth(EmailAuthApi api):super(FakeGoogleClient(),emailApi:api);
 Map<String,Object?>? submitted;
 @override Future<void> withdrawAccount(Map<String,Object?> request)async{submitted=request;}
}
void main(){
 test('account erasure removes only its scopes and pending claimed guest data',()async{
  String key(String scope)=>'weaver.owned.${base64Url.encode(utf8.encode(scope))}.weaver.workspace.v1';
  SharedPreferences.setMockInitialValues({key('email:a'):'private',key('email:a@workspace:w'):'shared-cache',key('email:b'):'other-account',key('guest-source'):'claimed','weaver.account.scopes.email:a':['email:a','email:b'],'weaver.guest.claim.v1':jsonEncode({'account':'email:a','scope':'guest-source'}),'weaver.selected-workspace.email:a':'w'});
  final prefs=await SharedPreferences.getInstance();final media=<String>[];
  await eraseAccountCache(prefs,'email:a',clearMedia:(scope)async{media.add(scope);});
  expect(prefs.getString(key('email:b')),'other-account');expect(prefs.containsKey(key('email:a')),false);expect(prefs.containsKey(key('email:a@workspace:w')),false);expect(prefs.containsKey(key('guest-source')),false);expect(prefs.containsKey('weaver.guest.claim.v1'),false);expect(media,unorderedEquals(['email:a','email:a@workspace:w','guest-source']));
 });
 for(final transfer in [false,true]){
 testWidgets('withdrawal requires verification and explicit workspace choice: transfer=$transfer',(tester)async{
  tester.view.physicalSize=const Size(1200,1800);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  var sent=0;
  final api=EmailAuthApi(store:MemorySessionStore(),client:MockClient((r)async{
   if(r.url.path.endsWith('/request')){sent++;return http.Response('{"sent":true}',200);}
   return http.Response(jsonEncode({'workspaces':[{'workspaceId':'12345678-space','members':[{'userId':'recipient','name':'Recipient','email':'r@example.invalid'}],'bytes':123}],'retention':'운영 데이터 즉시 삭제','sharedNotice':'다른 소유자의 자료는 유지'}),200,headers:{'content-type':'application/json; charset=utf-8'});
  }))..accessToken='server-token';
  final auth=WithdrawalAuth(api);await tester.pumpWidget(MaterialApp(home:WithdrawalPage(auth:auth)));await tester.pumpAndSettle();
  final submit=find.widgetWithText(FilledButton,'회원탈퇴');expect(tester.widget<FilledButton>(submit).onPressed,isNull);
  await tester.tap(find.byType(DropdownButtonFormField<String>));await tester.pumpAndSettle();await tester.tap(find.text(transfer?'Recipient에게 소유권 이전':'자료 전체 삭제').last);await tester.pumpAndSettle();
  await tester.tap(find.text('가입 이메일로 탈퇴 인증코드 받기'));await tester.pumpAndSettle();expect(sent,1);
  await tester.enterText(find.byType(TextField),'12345678');await tester.pumpAndSettle();
  await tester.tap(find.text('삭제 대상과 보관 안내를 확인했으며, 복구할 수 없다는 점에 동의합니다.'));await tester.pumpAndSettle();
  if(!transfer){expect(tester.widget<FilledButton>(submit).onPressed,isNull);await tester.tap(find.text('다른 참여자가 작성한 자료를 포함해 이 공간 전체를 삭제하는 데 동의합니다.'));await tester.pumpAndSettle();}
  expect(tester.widget<FilledButton>(submit).onPressed,isNotNull);await tester.tap(submit);await tester.pump(const Duration(milliseconds:300));expect(auth.submitted,isNull);
  await tester.tap(find.text('탈퇴').last);await tester.pumpAndSettle();
  expect(auth.submitted!['deleteWorkspaces'],transfer?isEmpty:['12345678-space']);expect(auth.submitted!['transfers'],transfer?{'12345678-space':'recipient'}:isEmpty);
  await tester.pumpWidget(const SizedBox());auth.dispose();
 });
 }
}
