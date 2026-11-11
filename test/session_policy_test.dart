import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'support/memory_session_store.dart';

Map<String,Object> native(String refresh) => {'id':'user','email':'user@example.com','expiresIn':1800,'accessToken':'access-$refresh','refreshToken':refresh};
http.Response ok(Object value) => http.Response(jsonEncode(value),200,headers:{'content-type':'application/json; charset=utf-8'});
void main() {
 test('Native restart restores from secure store without retaining password or access token', () async {
  final store=MemorySessionStore();
  final first=EmailAuthApi(store:store,client:MockClient((r) async => ok(native('first-refresh'))));
  await first.login('user@example.com','private-password');
  expect(store.value,contains('first-refresh'));expect(store.value,isNot(contains('private-password')));expect(store.value,isNot(contains('access-')));
  first.dispose();
  final restored=EmailAuthApi(store:store,client:MockClient((r) async {
   expect(r.url.path,endsWith('/native/refresh'));
   expect(jsonDecode(r.body)['refreshToken'],'first-refresh');
   return ok(native('rotated-refresh'));
  }));
  expect((await restored.restore())?['email'],'user@example.com');
  expect(jsonDecode(store.value!)['refreshToken'],'rotated-refresh');restored.dispose();
 });
 test('Lost refresh response retains request ID across app restart', () async {
  final store=MemorySessionStore();await store.write(jsonEncode({'refreshToken':'original'}));
  String? id;
  final failing=EmailAuthApi(store:store,client:MockClient((r) async {
   id=jsonDecode(r.body)['refreshId'];throw http.ClientException('offline');
  }));
  await expectLater(failing.restore(),throwsA(isA<EmailAuthFailure>()));
  expect(jsonDecode(store.value!)['requestId'],id);failing.dispose();
  final retry=EmailAuthApi(store:store,client:MockClient((r) async {
   expect(jsonDecode(r.body)['refreshId'],id);expect(jsonDecode(r.body)['refreshToken'],'original');return ok(native('next'));
  }));
  await retry.restore();expect(jsonDecode(store.value!),{'refreshToken':'next'});retry.dispose();
 });
 test('Invalid or revoked refresh clears credentials; temporary outage preserves them', () async {
  final store=MemorySessionStore();await store.write(jsonEncode({'refreshToken':'revoked'}));
  final api=EmailAuthApi(store:store,client:MockClient((_) async => http.Response('{"message":"expired"}',401)));
  expect(await api.restore(),isNull);expect(store.value,isNull);api.dispose();
 });
 test('Web reload reuses tab proof but a new tab cannot restore the session', () async {
  final tab=MemorySessionStore(isWeb:true);var calls=0;String? proof,id;
  http.Client client()=>MockClient((r) async {
   calls++;proof ??= r.headers['X-Weaver-Proof'];id ??= r.headers['X-Weaver-Tab'];
   expect(r.headers['X-Weaver-Proof'],proof);expect(r.headers['X-Weaver-Tab'],id);
   expect(r.headers.containsKey('Authorization'),isFalse);
   return ok({'id':'web','email':'web@example.com','expiresIn':1800});
  });
  final first=EmailAuthApi(store:tab,client:client());await first.login('web@example.com','private-password');first.dispose();
  expect(jsonDecode(tab.value!).keys.toSet(),{'id','proof'});
  expect(tab.value,isNot(contains('private-password')));
  final reload=EmailAuthApi(store:tab,client:client());expect((await reload.restore())?['id'],'web');reload.dispose();
  final newTab=EmailAuthApi(store:MemorySessionStore(isWeb:true),client:client());expect(await newTab.restore(),isNull);expect(calls,2);newTab.dispose();
 });
 test('Whole-account logout uses its own endpoint and clears device credentials only on success', () async {
  final store=MemorySessionStore();await store.write(jsonEncode({'refreshToken':'device'}));
  final api=EmailAuthApi(store:store,client:MockClient((r) async {
   expect(r.url.path,endsWith('/native/logout-all'));expect(jsonDecode(r.body)['refreshToken'],'device');return ok({'message':'ok'});
  }));
  await api.logout(all:true);expect(store.value,isNull);api.dispose();
 });
 test('Concurrent refresh calls share one rotation request', () async {
  final store=MemorySessionStore();await store.write(jsonEncode({'refreshToken':'device'}));
  var calls=0;
  final api=EmailAuthApi(store:store,client:MockClient((r) async {calls++;return ok(native('next-$calls'));}));
  await api.restore();calls=0;
  await Future.wait([api.refresh(),api.refresh(),api.refresh()]);expect(calls,1);api.dispose();
 });
}
