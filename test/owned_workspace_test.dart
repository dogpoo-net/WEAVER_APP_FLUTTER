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
 test('Guest import preserves already pending account edits',()async{
  final root=WorkspaceStorage(await SharedPreferences.getInstance());final owned=OwnedWorkspaces(root);await owned.initialize();final storage=owned.scope('account-a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  String identified(String title,String id){final value=jsonDecode(data(title)) as Map<String,dynamic>;value['notes'][0]['id']=id;return jsonEncode(value);}
  await storage.write(identified('pending account','account-note'));final guest=await owned.guest();await guest.write(identified('guest material','guest-note'));final claim=await owned.sealGuest('account-a',guest);await sync.importGuest(owned,claim);
  expect(storage.read(),contains('pending account'));expect(storage.read(),contains('guest material'));expect(guest.read(),isNull);expect(await owned.pendingClaim(),isNull);sync.dispose();api.dispose();
 });
 test('Deleting a thought syncs its tombstone without uploading unsaved document or canvas edits',()async{
  final prefs=await SharedPreferences.getInstance();final storage=WorkspaceStorage(prefs,owner:'device-a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  final first=jsonDecode(data('saved document')) as Map<String,dynamic>;
  final thought={'id':'thought-1','text':'delete me','createdAt':'2026-01-01T00:00:00.000','tags':[],'photos':[],'recordings':[],'inlineLinks':[]};
  first['elements']=[thought];first['graphLayout']={'positions':{'thought-1':[1,2]}};
  await storage.write(jsonEncode(first));await sync.flush();api.requests.clear();
  final edited=jsonDecode(jsonEncode(first)) as Map<String,dynamic>;
  edited['notes'][0]['content']='unsaved document';edited['graphLayout']['positions']['thought-1']=[40,80];
  edited['elements']=[];edited['trash']=[{...thought,'deletedAt':'2026-01-02T00:00:00.000'}];
  await storage.write(jsonEncode(edited));await storage.syncDeleted!();
  final changes=api.requests.single['changes'] as List;
  expect(changes.map((c)=>c['kind']).toSet(),{'list:elements','list:trash'});
  expect(changes.firstWhere((c)=>c['kind']=='list:elements')['deleted'],true);
  final other=WorkspaceStorage(prefs,owner:'device-b');final receiver=WorkspaceSync(other,api,isCurrent:()=>true);await receiver.initialize();
  final remote=jsonDecode(other.read()!) as Map;
  expect(remote['elements'],isEmpty);expect(remote['trash'],hasLength(1));expect(remote['notes'][0]['content'],'saved document');
  expect(remote['graphLayout']['positions']['thought-1'],[1,2]);
  expect(storage.read(),contains('unsaved document'));
  edited['trash']=[];await storage.write(jsonEncode(edited));await storage.syncDeleted!();
  expect((api.requests.last['changes'] as List).single['kind'],'list:trash');expect((api.requests.last['changes'] as List).single['deleted'],true);
  sync.dispose();receiver.dispose();api.dispose();
 });

 test('Browsing fetches remote deletions while preserving an unrelated local draft',()async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  final first=jsonDecode(data('saved')) as Map<String,dynamic>;first['elements']=[{'id':'remote-delete','text':'gone','createdAt':'2026-01-01T00:00:00.000','tags':[]}];
  await storage.write(jsonEncode(first));await sync.flush();first['notes'][0]['content']='pending local';await storage.write(jsonEncode(first));
  api.rev++;api.items[itemKey('list:elements','remote-delete')]={'kind':'list:elements','id':'remote-delete','deleted':true,'revision':api.rev,'payload':null};
  await storage.refreshNow!();final merged=jsonDecode(storage.read()!) as Map;
  expect(merged['elements'],isEmpty);expect(merged['notes'][0]['content'],'pending local');sync.dispose();api.dispose();
 });
 test('Folder deletion syncs only folder fields without uploading an unsaved document',()async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  final first=jsonDecode(data('saved')) as Map<String,dynamic>;first['folders']=['folder'];first['notes'][0]['folder']='folder';
  await storage.write(jsonEncode(first));await sync.flush();api.requests.clear();first['folders']=[];first['notes'][0]['folder']=null;first['notes'][0]['content']='pending local';await storage.write(jsonEncode(first));await storage.syncFolders!();
  final changes=api.requests.single['changes'] as List;expect(changes.firstWhere((c)=>c['kind']=='list:folders')['deleted'],true);
  final note=changes.firstWhere((c)=>c['kind']=='list:notes')['value'];expect(note['folder'],isNull);expect(note['content'],'saved');expect(storage.read(),contains('pending local'));sync.dispose();api.dispose();
 });

 test('Browsing another section never replaces an active document editor snapshot',()async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final api=DeltaApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  final initial=jsonDecode(data('original')) as Map<String,dynamic>;
  initial['notes'][0]['id']='n';initial['notes'][0]['project']={'id':'p','name':'Document','document':'original','words':[],'paragraphs':[],'tags':[],'documentLinks':[]};
  await storage.write(jsonEncode(initial));await sync.flush();sync.documentLeases['p']='lease';
  final changed=jsonDecode(jsonEncode(initial['notes'][0])) as Map<String,dynamic>;changed['project']['document']='remote change';changed['content']='remote change';api.rev++;
  api.items[itemKey('list:notes','n')]={'kind':'list:notes','id':'n','payload':jsonEncode(changed),'revision':api.rev,'deleted':false};
  await sync.refreshFromServer();expect(storage.read(),contains('original'));expect(storage.read(),isNot(contains('remote change')));
  sync.documentLeases.clear();await sync.refreshFromServer();expect(storage.read(),contains('remote change'));sync.dispose();api.dispose();
 });

}
