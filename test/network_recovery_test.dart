import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'package:weaver/features/sync/network_recovery.dart';
import 'owned_workspace_test.dart' show DeltaApi;
class NetworkApi extends DeltaApi {
 bool disconnected=false;int? rejected;Future<void> Function()? afterSave;
 @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body)async{
  if(disconnected)throw const EmailAuthFailure('offline',networkUnavailable:true);
  if(rejected!=null)throw EmailAuthFailure('rejected',status:rejected);
  final result=await super.workspace(action,body);
  if(action=='save'&&afterSave!=null){final callback=afterSave!;afterSave=null;await callback();}
  return result;
 }
}
String snapshot(List<String> folders)=>jsonEncode({'version':1,'elements':[],'notes':[],'trash':[],'colors':{},'folders':folders});
void main(){
 test('three-way merge preserves server-only items and finds edit/delete collisions',(){
  Map<String,dynamic> item(String value)=>{'kind':'list:folders','id':'a','value':value};
  final before={'a':item('old')},local={'a':item('local')},remote={'a':item('server'),'b':item('new')};
  final plan=NetworkRecoveryPlan(before,local,remote);expect(plan.conflicts,{'a'});expect(plan.merged['b'],remote['b']);
  expect(NetworkRecoveryPlan(before,{},remote).conflicts,{'a'});
  expect(NetworkRecoveryPlan(before,local,local).changes,isEmpty);
 });
 test('network loss keeps paid cache writable and automatically merges disjoint changes',()async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'paid');final api=NetworkApi();
  final sync=WorkspaceSync(storage,api,isCurrent:()=>true,workspaceId:'paid');addTearDown(sync.dispose);
  await sync.initialize();await storage.write(snapshot(['original']));await sync.flush();
  api.disconnected=true;await expectLater(sync.request('status',{}),throwsA(isA<EmailAuthFailure>()));
  expect(storage.offlineMode,true);await storage.write(snapshot(['original','local']));await sync.flush();
  api.disconnected=false;await api.workspace('save',{'changes':[{'kind':'list:folders','id':'remote','value':'remote','deleted':false}]});
  await sync.recoverNetwork();expect(sync.networkPending,false);expect(storage.offlineMode,false);
  expect(jsonDecode(storage.read()!)['folders'],containsAll(['original','local','remote']));
 });
 test('a newer local edit during reconnect save is retained for the next reconciliation',()async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'paid');final api=NetworkApi();final sync=WorkspaceSync(storage,api,isCurrent:()=>true);addTearDown(sync.dispose);
  await sync.initialize();await sync.enterNetworkOffline();await storage.write(snapshot(['first']));
  api.afterSave=()=>storage.write(snapshot(['first','later']));
  await sync.recoverNetwork();expect(sync.networkPending,true);expect(jsonDecode(storage.read()!)['folders'],contains('later'));
  await sync.recoverNetwork();expect(sync.networkPending,false);expect(jsonDecode(storage.read()!)['folders'],containsAll(['first','later']));
 });
 test('conflicts survive restart and wait without sending a save',()async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'paid');final api=NetworkApi();
  final key=itemKey('list:elements','a');
  Map<String,dynamic> row(String text)=>{'kind':'list:elements','id':'a','value':{'id':'a','text':text,'createdAt':'2026-01-01T00:00:00.000Z','tags':[]},'revision':1};
  final sync=WorkspaceSync(storage,api,isCurrent:()=>true);sync.base={key:row('base')};await sync.saveBase();await storage.replaceFromBackup(joinWorkspace({key:row('local')}));await sync.enterNetworkOffline();sync.dispose();
  api.items[key]={'kind':'list:elements','id':'a','payload':jsonEncode(row('remote')['value']),'revision':2,'deleted':false};api.rev=2;
  final restored=WorkspaceSync(storage,api,isCurrent:()=>true);addTearDown(restored.dispose);await restored.initialize();await restored.recoverNetwork();
  expect(restored.needsRecoveryReview,true);expect(api.requests,isEmpty);expect(splitWorkspace(storage.read())[key]!['value']['text'],'local');
 });
 for(final status in [401,403,500]){test('HTTP $status is not mistaken for network loss',()async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'x');final api=NetworkApi()..rejected=status;final sync=WorkspaceSync(storage,api,isCurrent:()=>true);addTearDown(sync.dispose);
  await expectLater(sync.request('status',{}),throwsA(isA<EmailAuthFailure>()));expect(sync.networkPending,false);
 });}
}
