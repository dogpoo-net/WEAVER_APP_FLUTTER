import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/overview_tab_settings.dart';
import 'package:weaver/features/inbox/workspace_search.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/capture/capture_models.dart';
void main(){
 setUp((){SharedPreferences.setMockInitialValues({});elements.clear();});
 test('searches documents, thoughts and saved transcripts, excluding trash',(){
  final p=WritingProject([],[],name:'계획')..document='서울 회의';
  final note=Note(p.content)..project=p;
  final r=elements.add('서울 일정')..recordings.add(const VoiceAttachment('v',1000,transcript:'서울 회의 녹음'));
  final deleted=ElementRecord('서울 삭제')..deletedAt=DateTime.now();
  final results=searchWorkspace([note],[r,deleted],'서울');
  expect(results.map((r)=>r.kind),['문서','생각','음성']);
  expect(searchWorkspace([note],[r],'회의 서울').length,2);
  expect(searchWorkspace([note],[r],'  '),isEmpty);
  expect(VoiceAttachment.fromJson(r.recordings.single.toJson()).transcript,'서울 회의 녹음');
  expect(VoiceAttachment.fromJson({'id':'old','durationMs':1000}).transcript,'');
 });
 test('tab configuration persists and ignores retired tabs',()async{
  await saveOverviewTabs(OverviewTabs(['audio','diagram','search','audio'],{'search'}));
  final result=await loadOverviewTabs(['search','documents','audio']);
  expect(result.order,['audio','search','documents']);expect(result.hidden,{'search'});
 });
 testWidgets('search opens document and gear tab configures visibility and order',(tester)async{
  tester.view.physicalSize=const Size(1200,900);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final p=WritingProject([],[],name:'계획')..document='서울 회의';final note=Note(p.content)..project=p;
  var opened=false;
  await tester.pumpWidget(MaterialApp(home:AllThoughtsPage(notes:[note],initialView:ThoughtView.search,onDocument:(n)async{opened=n.id==note.id;})));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('workspace-search')),'서울');await tester.pump(const Duration(milliseconds:250));
  await tester.tap(find.byKey(ValueKey('search-문서-${note.id}')));await tester.pump();expect(opened,isTrue);
  await tester.tap(find.byKey(const ValueKey('overview-tab-settings')));await tester.pumpAndSettle();
  final list=tester.widget<ReorderableListView>(find.byType(ReorderableListView));list.onReorderItem!(0,2);await tester.pump();
  await tester.tap(find.descendant(of:find.byKey(const ValueKey('tab-setting-photos')),matching:find.byType(Switch)));await tester.pump();
  await tester.tap(find.text('적용'));await tester.pumpAndSettle();
  expect(find.text('사진'),findsNothing);expect(find.byKey(const ValueKey('overview-tab-settings')),findsOneWidget);
  final saved=await loadOverviewTabs(activeThoughtViews.map((v)=>v.name).toList());expect(saved.order[2],'search');expect(saved.hidden,contains('photos'));
  await tester.pumpWidget(const SizedBox());
 });
}
