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
 final receipts=<String>{}; bool loseResponse=false;Completer<void>? entered,release;
 @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body)async{
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
 test('readonly workspace never schedules automatic writes',()async{
  final api=ReceiptApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true,readOnly:true);await sync.initialize();
  await storage.write(snapshot({'a':[1,2]}));await sync.flushCanvas();expect(api.requests,isEmpty);expect(storage.canvasWritable,false);sync.dispose();api.dispose();
 });
}
