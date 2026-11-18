import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'package:weaver/features/sync/workspace_sync_review.dart';
import 'owned_workspace_test.dart' show DeltaApi;
void main(){
 test('review requires explicit choices and only overwrites chosen objects',(){
  final local={itemKey('list:folders','local'):{'kind':'list:folders','id':'local','value':'local'}};
  final remote={itemKey('list:folders','server'):{'kind':'list:folders','id':'server','value':'server','revision':7}};
  final differences=syncDifferences(local,remote);
  expect(()=>reviewChanges(differences,{},local,remote),throwsStateError);
  final keepServer={for(final d in differences)d.id:false};expect(reviewChanges(differences,keepServer,local,remote),isEmpty);
  final chosen={for(final d in differences)d.id:d.keys.contains(itemKey('list:folders','local'))};
  final changes=reviewChanges(differences,chosen,local,remote);expect(changes.length,1);expect(changes.single['id'],'local');expect(changes.single['deleted'],false);
 });
 testWidgets('discard local changes uses server snapshot without a save request',(tester)async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'account');
  String snapshot(String folder)=>jsonEncode({'version':1,'elements':[],'notes':[],'trash':[],'colors':{},'folders':[folder]});
  await storage.write(snapshot('local'));
  final api=DeltaApi();api.rev=1;
  for(final item in splitWorkspace(snapshot('server')).values){api.items[itemKey(item['kind'],item['id'])]={...item,'payload':jsonEncode(item['value']),'revision':1,'deleted':false};}
  final engine=WorkspaceSync(storage,api,workspaceId:'workspace',isCurrent:()=>true);await engine.beginReview();
  await tester.pumpWidget(MaterialApp(home:WorkspaceSyncReviewPage(engine:engine,source:storage)));await tester.pumpAndSettle();
  expect(api.requests,isEmpty);
  for(final chip in find.widgetWithText(ChoiceChip,'로컬 변경 버리고 서버 사용').evaluate().toList()){
    await tester.ensureVisible(find.byWidget(chip.widget));await tester.tap(find.byWidget(chip.widget));await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text('선택한 내용 적용'));await tester.tap(find.text('선택한 내용 적용'));await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton,'적용'));await tester.pumpAndSettle();
  expect(api.requests,isEmpty);expect(jsonDecode(storage.read()!)['folders'],['server']);
  engine.dispose();api.dispose();
 });
}
