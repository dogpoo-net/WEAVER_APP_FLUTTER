import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'support/test_server_auth.dart';
import 'support/memory_session_store.dart';
import 'google_auth_test.dart' show FakeGoogleClient;
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('Old remembered Google marker never authenticates a workspace',()async{
  final prefs=await SharedPreferences.getInstance();await prefs.setString(GoogleAuthController.rememberedAccountKey,jsonEncode({'id':'old','email':'old@example.com'}));
  final auth=GoogleAuthController(FakeGoogleClient(),preferences:prefs,emailApi:testServerAuth());await auth.initialize();expect(auth.identity,isNull);expect(auth.canUseCloud,isFalse);auth.dispose();
 });
 test('Google login is exchanged for a server session and restored from secure credentials',()async{
  final prefs=await SharedPreferences.getInstance();final store=MemorySessionStore();
  final first=GoogleAuthController(FakeGoogleClient(),preferences:prefs,emailApi:testServerAuth(store:store));await first.initialize();await first.signIn();await Future<void>.delayed(Duration.zero);
  expect(first.identity?.id,'email:server-user');expect(first.identity?.idToken,isNull);expect(store.value,contains('refresh'));expect(store.value,isNot(contains('test-token')));expect(prefs.getString(GoogleAuthController.rememberedAccountKey),isNull);first.dispose();
  final second=GoogleAuthController(FakeGoogleClient(),preferences:prefs,emailApi:testServerAuth(store:store));await second.initialize();expect(second.identity?.id,'email:server-user');await second.signOut();expect(store.value,isNull);expect(second.isGuest,isTrue);second.dispose();
 });
}
