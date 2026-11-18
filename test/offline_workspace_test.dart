import 'dart:convert';
import 'owned_workspace_test.dart' show DeltaApi;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/offline_workspace.dart';
import 'package:weaver/features/sync/workspace_backup.dart';
import 'package:weaver/features/sync/workspace_file_transfer.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
class MemoryMedia implements BackupMedia{
 final data=<String,Uint8List>{};
 @override Future<Uint8List?> read(String id)async=>data[id];
 @override Future<void> write(String id,Uint8List bytes)async{data[id]=bytes;}
 @override Future<void> delete(String id)async{data.remove(id);}
}
String snapshot(String name)=>jsonEncode({'version':1,'elements':[],'trash':[],'notes':[],'colors':{},'folders':[name]});
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('offline publish rejects conflicting geometry and keeps baseline and local copy',()async{
  final prefs=await SharedPreferences.getInstance(),local=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'offline');
  String layout(int x)=>jsonEncode({'version':1,'elements':[],'trash':[],'notes':[],'colors':{},'memoBoxes':[{'name':'box','color':0,'ids':[],'layout':{'positions':{'memo':[x,20]}}}]});
  await local.write(layout(2));await prefs.setString(OfflineWorkspace.baseline(local),layout(1));
  expect(()=>OfflineWorkspace.delta(local,splitWorkspace(layout(3))),throwsA(isA<Exception>()));
  expect(local.read(),layout(2));expect(prefs.getString(OfflineWorkspace.baseline(local)),layout(1));
  expect(OfflineWorkspace.delta(local,splitWorkspace(layout(2))),isEmpty);
 });
 test('offline delta does not remove server-only items',()async{
  final prefs=await SharedPreferences.getInstance(),local=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'offline');
  await local.write(snapshot('local'));await prefs.setString(OfflineWorkspace.baseline(local),snapshot('old'));
  final remote=splitWorkspace(snapshot('old'))..addAll(splitWorkspace(snapshot('server-addition')));
  final delta=OfflineWorkspace.delta(local,remote);
  expect(delta.any((item)=>item['id']=='server-addition'),false);
 });
 test('online return refreshes stale canvas without uploading it and preserves recovery',()async{
  final prefs=await SharedPreferences.getInstance();final online=WorkspaceStorage(prefs,owner:'online'),local=WorkspaceStorage(prefs,owner:'offline');
  String layout(int x)=>jsonEncode({'version':1,'elements':[],'trash':[],'notes':[],'colors':{},'memoBoxes':[{'name':'box','color':0,'ids':[],'layout':{'positions':{'memo':[x,20]}}}]});
  final api=DeltaApi();
  void remote(int x){api.rev++;for(final item in splitWorkspace(layout(x)).values){api.items[itemKey(item['kind'],item['id'])]={...item,'payload':jsonEncode(item['value']),'deleted':false,'revision':api.rev};}}
  remote(1);final first=WorkspaceSync(online,api,isCurrent:()=>true);await first.initialize();first.dispose();
  await online.write(layout(2));await local.write(layout(2));await prefs.setString(online.scoped('canvas.outbox.v1'),'old pending operation');await OfflineWorkspace.preserveRecovery(local,online);
  remote(3);final sync=WorkspaceSync(online,api,isCurrent:()=>true);await sync.initialize(serverCanvas:true);await sync.flushCanvas();
  expect(jsonDecode(online.read()!)['memoBoxes'][0]['layout']['positions']['memo'],[3,20]);expect(api.requests,isEmpty);expect(prefs.getString(online.scoped('canvas.outbox.v1')),isNull);
  final recovery=jsonDecode(prefs.getString(local.scoped('offline-recovery'))!);expect(recovery['online'],layout(2));expect(recovery['offline'],layout(2));
  sync.dispose();api.dispose();
 });
 test('file import only replaces selected local workspace, not another account or space',()async{
  final prefs=await SharedPreferences.getInstance();
  final a=WorkspaceStorage(prefs,owner:OfflineWorkspace.owner('account-a','space-a'));
  final b=WorkspaceStorage(prefs,owner:OfflineWorkspace.owner('account-a','space-b'));
  final c=WorkspaceStorage(prefs,owner:OfflineWorkspace.owner('account-b','space-a'));
  await a.write(snapshot('old'));await b.write(snapshot('other'));await c.write(snapshot('other-account'));
  await applyWorkspaceBackup(WorkspaceBackup.decode(snapshot('imported')),a,mediaStore:MemoryMedia());
  expect(jsonDecode(a.read()!)['folders'],['imported']);expect(b.read(),snapshot('other'));expect(c.read(),snapshot('other-account'));
 });
 test('offline scope is distinct and dirty work survives seeding',()async{
  final prefs=await SharedPreferences.getInstance();final local=WorkspaceStorage(prefs,owner:OfflineWorkspace.owner('a','w'));final online=WorkspaceStorage(prefs,owner:'a@workspace:w');
  await online.write(snapshot('server'));await OfflineWorkspace.seed(local,online);expect(local.read(),online.read());expect(OfflineWorkspace.hasChanges(local),false);
  await local.write(snapshot('local-change'));await online.write(snapshot('new-server'));await OfflineWorkspace.seed(local,online);expect(local.read(),snapshot('local-change'));expect(online.read(),snapshot('new-server'));
 });
 test('offline published clean copy can pick up subsequent online work',()async{
  final prefs=await SharedPreferences.getInstance();final local=WorkspaceStorage(prefs,owner:'offline');final online=WorkspaceStorage(prefs,owner:'online');await online.write(snapshot('one'));await OfflineWorkspace.seed(local,online);await online.write(snapshot('two'));await OfflineWorkspace.seed(local,online);expect(local.read(),snapshot('two'));
 });
 test('offline delta includes only locally changed items',()async{
  final prefs=await SharedPreferences.getInstance();final local=WorkspaceStorage(prefs,owner:'offline');await local.write(snapshot('new'));await prefs.setString(OfflineWorkspace.baseline(local),snapshot('old'));final delta=OfflineWorkspace.delta(local,splitWorkspace(snapshot('old')));expect(delta.length,2);expect(delta.where((c)=>c['deleted']==true).single['id'],'old');
 });
 test('malformed backup is rejected before changing local content',()async{
  final prefs=await SharedPreferences.getInstance();final local=WorkspaceStorage(prefs,owner:'a');await local.write(snapshot('keep'));expect(()=>WorkspaceBackup.decode('{invalid'),throwsA(anything));expect(local.read(),snapshot('keep'));
 });
}
