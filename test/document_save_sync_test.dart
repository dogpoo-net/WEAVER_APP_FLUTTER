import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'package:weaver/features/sync/document_merge.dart';
import 'support/memory_session_store.dart';
import 'document_merge_test.dart' show note;
class DocumentApi extends EmailAuthApi {
 DocumentApi():super(store:MemorySessionStore(isWeb:true));
 int revision=1,saves=0;late Map<String,dynamic> row;bool raceOnce=false;
 void set(String text){final value=note(text)..addAll({'createdAt':'2026-01-01T00:00:00.000','tags':[],'bindings':[]});row={'kind':'list:notes','id':'n','value':value,'payload':jsonEncode(value),'revision':revision,'deleted':false};}
 @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body)async{
  if(action=='save'){
   expect(body['documentMerge'],true);expect(body['documentLeases'],isNull);
   final c=(body['changes'] as List).single;
   if(c['baseRevision']!=revision)return {'revision':revision,'documentConflict':Map.of(row)};
   if(raceOnce){raceOnce=false;revision++;set('a\nB\nC');return {'revision':revision,'documentConflict':Map.of(row)};}
   revision++;saves++;row={'kind':'list:notes','id':'n','payload':jsonEncode(c['value']),'revision':revision,'deleted':false};
  }
  return {'revision':revision,'changes':[Map.of(row)]};
 }
}
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('save merges a second concurrent save and commits with checked revision',()async{
  final api=DocumentApi()..set('a\nb\nc');final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  storage.documentSaveBases['p']=Map.of(sync.base.values.single);final value=jsonDecode(storage.read()!);value['notes'][0]['project']['document']='A\nb\nc';value['notes'][0]['content']='A\nb\nc';await storage.write(jsonEncode(value));
  api.revision++;api.set('a\nB\nc');api.raceOnce=true;
  await storage.syncResource!('p');expect(api.saves,1);expect(jsonDecode(api.row['payload'])['project']['document'],'A\nB\nC');
  sync.dispose();api.dispose();
 });
 test('conflicting save preserves local draft and leaves server unchanged',()async{
  final api=DocumentApi()..set('a\nb');final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'a');final sync=WorkspaceSync(storage,api,isCurrent:()=>true);await sync.initialize();
  storage.documentSaveBases['p']=Map.of(sync.base.values.single);final value=jsonDecode(storage.read()!);value['notes'][0]['project']['document']='a\nMINE';await storage.write(jsonEncode(value));await storage.writeDocumentDraft('p',{'text':'a\nMINE'});
  api.revision++;api.set('a\nSERVER');await expectLater(storage.syncResource!('p'),throwsA(isA<DocumentMergeConflict>()));expect(api.saves,0);expect(storage.documentDraft('p')!['saved'],0);expect(storage.read(),contains('MINE'));sync.dispose();api.dispose();
 });
}
