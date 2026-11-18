import 'package:weaver/features/inbox/memo_comment_count.dart';
import 'package:weaver/features/inbox/memo_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_search.dart';
import 'package:weaver/features/inbox/overview_collections.dart';
import 'package:weaver/features/inbox/overview_tab_activity.dart';

void main(){
 testWidgets('hidden tab defers comment rebuild until resumed',(tester)async{
  var active=true,builds=0;late StateSetter update;
  memoCommentCounts.value={};
  final child=MemoCommentCount(id:'memo',builder:(context,count){builds++;return Text('$count');});
  await tester.pumpWidget(MaterialApp(home:StatefulBuilder(builder:(context,set){update=set;return OverviewTabActivity(active:active,child:child);})));
  update(()=>active=false);await tester.pump();final before=builds;
  memoCommentCounts.value={'memo':3};await tester.pump();expect(builds,before);
  update(()=>active=true);await tester.pump();expect(find.text('3'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());memoCommentCounts.value={};
 });
 setUp((){SharedPreferences.setMockInitialValues({});elements.clear();});
 testWidgets('visited desktop tabs retain search pagination and update on return',(tester)async{
  tester.view.physicalSize=const Size(1200,900);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  for(var i=0;i<45;i++){elements.add('memo $i');}
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[],initialView:ThoughtView.search)));
  await tester.pumpAndSettle();
  expect(find.byType(DocumentCollection,skipOffstage:false),findsNothing);
  final state=tester.state(find.byType(WorkspaceSearch));
  final list=find.byKey(const ValueKey('workspace-search-results'));
  final scroll=tester.widget<ListView>(list).controller!;
  scroll.jumpTo(scroll.position.maxScrollExtent);await tester.pump();
  final offset=scroll.offset;
  await tester.tap(find.widgetWithText(TextButton,'문서'));await tester.pumpAndSettle();
  expect(find.byType(WorkspaceSearch),findsNothing);
  expect(tester.state(find.byType(WorkspaceSearch,skipOffstage:false)),same(state));
  elements.add('새 자료');elements.refreshVisibility();await tester.pump();
  await tester.tap(find.widgetWithText(TextButton,'검색'));await tester.pumpAndSettle();
  expect(tester.state(find.byType(WorkspaceSearch)),same(state));
  expect(scroll.offset,offset);
  expect(tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,79);
  scroll.jumpTo(0);await tester.pump();expect(find.text('생각: 새 자료'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('overview reopens last selected tab but explicit routes take precedence',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[])));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton,'문서'));await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[])));
  await tester.pumpAndSettle();
  expect(find.byType(DocumentCollection),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[],initialView:ThoughtView.search)));
  await tester.pumpAndSettle();
  expect(find.byType(WorkspaceSearch),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('hidden remembered tab falls back to visible tab',(tester)async{
  SharedPreferences.setMockInitialValues({
   'weaver.overviewLastTab.v1':'documents',
   'weaver.overviewTabs.v1':'{"order":["search","documents"],"hidden":["documents"]}',
  });
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[])));
  await tester.pumpAndSettle();
  expect(find.byType(WorkspaceSearch),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('mobile retains only three visited tabs',(tester)async{
  tester.view.physicalSize=const Size(400,800);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[],initialView:ThoughtView.search)));
  await tester.pumpAndSettle();
  for(final title in ['문서','생각','사진']){
    final tab=find.widgetWithText(TextButton,title);await tester.ensureVisible(tab);await tester.tap(tab);await tester.pumpAndSettle();
  }
  expect(find.byType(OverviewTabActivity,skipOffstage:false),findsNWidgets(3));
  expect(find.byType(WorkspaceSearch,skipOffstage:false),findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
}
