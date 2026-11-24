import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'owned_workspace_test.dart' show DeltaApi;

String snapshot(Map<String,dynamic> positions)=>jsonEncode({'version':1,'elements':[],'notes':[],'trash':[],'colors':{},'graphLayout':{'positions':positions}});
class ReceiptApi extends DeltaApi {
 Completer<void>? readEntered, readRelease;
 final receipts=<String>{}; bool loseResponse=false;Completer<void>? entered,release;
 @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body)async{
  if(action=='read' && readEntered!=null){
   final result=await super.workspace(action,body);
   readEntered!.complete();await readRelease!.future;return result;
  }
  if(action=='save'&&body['canvasOperationId']!=null){
   final id=body['canvasOperationId'] as String;
   if(receipts.contains(id))return {'revision':rev,'changes':items.values.toList()};
   final result=await super.workspace(action,body);receipts.add(id);
   if(entered!=null){entered!.complete();await release!.future;}
   if(loseResponse){loseResponse=false;throw const EmailAuthFailure('lost response');}
   return result;
  }
  return super.workspace(action,body);
 }
}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('geometry merge retains active local move and accepts other remote objects',(){
  final baseline=GraphLayout()..positions.addAll({'a':Offset.zero,'b':Offset.zero});
  final local=GraphLayout.fromJson(baseline.toJson())..positions['a']=const Offset(10,20);
  final remote=GraphLayout.fromJson(baseline.toJson())..positions.addAll({'a':const Offset(90,90),'b':const Offset(40,50)});
  local.mergeRemote(remote,baseline);
  expect(local.positions,{'a':const Offset(10,20),'b':const Offset(40,50)});
 });
 test('canvas sends changed leaves only without document or viewport and without lease',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true);
  await sync.initialize();await storage.write(snapshot({'a':[1,2],'b':[3,4]}));await sync.flushCanvas();api.requests.clear();
  final data=jsonDecode(snapshot({'a':[5,6],'b':[3,4]}));data['graphLayout']['query']='local search';
  data['notes']=[{'id':'doc','content':'unsaved','createdAt':'2026-01-01','project':{'id':'doc','name':'doc','paragraphs':[],'words':[]}}];
  await storage.write(jsonEncode(data));await sync.flushCanvas();
  final request=api.requests.single;expect(request['resourceId'],isNull);expect(request['documentLeases'],isNull);
  expect((request['changes'] as List).length,1);expect((request['changes'] as List).single['id'],'["page","positions","a"]');
  sync.dispose();api.dispose();
 });
 test('offline local layout survives a restart and remote refresh',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');var sync=WorkspaceSync(storage,api,isCurrent:()=>true);
  await sync.initialize();await storage.write(snapshot({'a':[1,2]}));await sync.flushCanvas();
  await storage.write(snapshot({'a':[10,20]}));api.fail=true;await expectLater(sync.flushCanvas(),throwsA(isA<EmailAuthFailure>()));sync.dispose();
  api.fail=false;sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  expect(jsonDecode(storage.read()!)['graphLayout']['positions']['a'],[10,20]);await sync.flushCanvas();
  expect(storage.canvasSaveState.value,'저장됨');sync.dispose();api.dispose();
 });
 test('lost response retry does not replay over a later collaborators move',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  await storage.write(snapshot({'a':[10,20]}));api.loseResponse=true;await expectLater(sync.flushCanvas(),throwsA(isA<EmailAuthFailure>()));
  final key=itemKey('layout','["page","positions","a"]');api.items[key]!['payload']='[90,100]';api.items[key]!['revision']=++api.rev;
  await sync.flushCanvas();expect(api.requests.length,1);expect(jsonDecode(storage.read()!)['graphLayout']['positions']['a'],[90,100]);
  sync.dispose();api.dispose();
 });
 test('save acknowledgement never rolls back a newer local move',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  await storage.write(snapshot({'a':[10,20]}));api.entered=Completer();api.release=Completer();final saving=sync.flushCanvas();await api.entered!.future;
  await storage.write(snapshot({'a':[30,40]}));api.release!.complete();await saving;
  expect(jsonDecode(storage.read()!)['graphLayout']['positions']['a'],[30,40]);
  api.entered=null;api.release=null;await sync.flushCanvas();expect(jsonDecode(api.items.values.first['payload']),[30,40]);
  sync.dispose();api.dispose();
 });
 test('SSE refresh spanning a second drag retries without losing either edit',()async{
  final api=ReceiptApi();
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');
  final sync=WorkspaceSync(storage,api,isCurrent:()=>true);
  await sync.initialize();
  await storage.write(snapshot({'a':[10,20],'b':[1,1]}));await sync.flushCanvas();
  final b=itemKey('layout','["page","positions","b"]');
  api.items[b]!['payload']='[7,8]';api.items[b]!['revision']=++api.rev;
  api.readEntered=Completer();api.readRelease=Completer();
  final refresh=sync.refreshFromServer();await api.readEntered!.future;
  storage.canvasInteracting=true;
  await storage.write(snapshot({'a':[30,40],'b':[1,1]}));
  storage.canvasInteracting=false;
  api.readRelease!.complete();await refresh;
  dynamic points()=>jsonDecode(storage.read()!)['graphLayout']['positions'];
  expect(points(),{'a':[30,40],'b':[1,1]});
  api.readEntered=null;await sync.refreshFromServer();
  expect(points(),{'a':[30,40],'b':[7,8]});
  await sync.flushCanvas();
  expect(jsonDecode(api.items[itemKey('layout','["page","positions","a"]')]!['payload']),[30,40]);
  sync.dispose();api.dispose();
 });
 test('acknowledging our own canvas move does not rebuild or replace the workspace',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  var applied=0;storage.applyServerSnapshot=()=>applied++;
  final raw=snapshot({'a':[10,20]});await storage.write(raw);await sync.flushCanvas();
  expect(applied,0);expect(storage.read(),raw);expect(api.requests.length,1);
  sync.dispose();api.dispose();
 });
 test('identical persistence does not notify or replace the recovery checkpoint',()async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');var changes=0;storage.onChanged=()=>changes++;
  final before=snapshot({'a':[1,2]}),after=snapshot({'a':[3,4]});await storage.write(before);await storage.write(after);
  for(var i=0;i<20;i++){await storage.write(after);}
  expect(changes,2);expect(storage.preferences.getString('${storage.workspaceKey}.previous'),before);
 });
 test('readonly workspace never schedules automatic writes',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true,readOnly:true);await sync.initialize();
  await storage.write(snapshot({'a':[1,2]}));await sync.flushCanvas();expect(api.requests,isEmpty);expect(storage.canvasWritable,false);sync.dispose();api.dispose();
 });
}
