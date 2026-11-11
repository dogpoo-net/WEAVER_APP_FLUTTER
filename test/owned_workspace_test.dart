import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'support/memory_session_store.dart';
class DeltaApi extends EmailAuthApi {
 DeltaApi():super(store:MemorySessionStore(isWeb:true));
 final items=<String,Map<String,dynamic>>{};final requests=<Map<String,Object?>>[];int rev=0;bool fail=false;
 @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body)async {
  if(fail)throw const EmailAuthFailure('offline');
  if(action=='save'||action=='claim'){
   requests.add(body);rev++;
   for(final raw in body['changes'] as List){final c=Map<String,dynamic>.from(raw as Map);items[itemKey(c['kind'],c['id'])]={'kind':c['kind'],'id':c['id'],'payload':c['deleted']==true?null:jsonEncode(c['value']),'deleted':c['deleted'],'revision':rev};}
  }
  return {'revision':rev,'changes':items.values.toList()};
 }
}
String data(String title)=>jsonEncode({'version':1,'colors':{},'elements':[],'trash':[],'notes':[{'content':title,'createdAt':'2026-01-01T00:00:00.000','tags':[],'bindings':[]}]});
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('Account caches are never a guest source, including expired-session restarts',()async{
  final p=await SharedPreferences.getInstance();final owned=OwnedWorkspaces(WorkspaceStorage(p));await owned.initialize();
  await owned.scope('account-a').write(data('private A'));
  expect((await owned.guest()).read(),isNull);expect(owned.scope('account-b').read(),isNull);expect(owned.scope('account-a').read(),contains('private A'));
 });
 test('Unowned legacy account data is quarantined, never imported as guest',()async{
  final p=await SharedPreferences.getInstance();final root=WorkspaceStorage(p);await root.write(data('legacy'));final owned=OwnedWorkspaces(root);await owned.initialize();
  expect(root.read(),isNull);expect(owned.scope('quarantine').read(),contains('legacy'));expect((await owned.guest()).read(),isNull);
 });
 test('Sealing guest data blocks late writes and creates a new empty guest generation',()async{
  final owned=OwnedWorkspaces(WorkspaceStorage(await SharedPreferences.getInstance()));await owned.initialize();final guest=await owned.guest();await guest.write(data('guest'));
  final claim=await owned.sealGuest('account-a',guest);expect(claim['account'],'account-a');
  await expectLater(guest.write(data('late')),throwsStateError);
  final fresh=await owned.guest();expect(fresh.owner,isNot(guest.owner));expect(fresh.read(),isNull);
  final retry=await owned.sealGuest('account-b',fresh);expect(retry['account'],'account-a');
  await owned.finishClaim(claim);expect(guest.read(),isNull);expect((await owned.guest()).owner,fresh.owner);
 });
 test('Only changed entries are sent; local changes do not trigger periodic requests',()async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'account-a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  await storage.write(data('first'));expect(api.requests,isEmpty);await sync.flush();
  api.requests.clear();await storage.write(data('edited'));await sync.flush();
  final changes=api.requests.single['changes'] as List;expect(changes.length,1);expect(changes.single['kind'],'list:notes');sync.dispose();api.dispose();
 });
 test('Offline unsynced data survives logout cleanup and successful data can be cleared',()async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'account-a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();await storage.write(data('unsent'));api.fail=true;
  await expectLater(sync.flush(),throwsA(isA<EmailAuthFailure>()));await sync.removeCleanCache();expect(storage.read(),contains('unsent'));
  api.fail=false;await sync.flush();await sync.removeCleanCache();expect(storage.read(),isNull);sync.dispose();api.dispose();
 });
}
