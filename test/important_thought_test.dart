import 'package:weaver/features/capture/attachment_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/packed_badges.dart';
void main(){
 setUp((){elements.clear();SharedPreferences.setMockInitialValues({});});
 testWidgets('importance is the first indicator before comments in both layouts',(tester)async{
  final record=ElementRecord('중요')..important=true;
  for(final vertical in [true,false]){
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:AttachmentIndicators(record:record,commentCount:3,vertical:vertical))));
   expect(tester.widgetList<Icon>(find.byType(Icon)).map((i)=>i.icon),[Icons.priority_high,Icons.chat_bubble_outline]);
  }
 });
 test('important status round trips and sorts ahead of newer ordinary thoughts',(){
  final old=ElementRecord.restored('old','중요',DateTime(2020))..important=true;
  final newer=ElementRecord.restored('new','일반',DateTime(2026));
  final latest=ElementRecord.restored('last','최근 중요',DateTime(2025))..important=true;
  elements.records.addAll({old.text:old,newer.text:newer,latest.text:latest});
  final snapshot=WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
  final sorted=snapshot.records..sort(compareThoughtPriority);
  expect(sorted.map((r)=>r.id),['last','old','new']);expect(sorted.last.important,isFalse);
 });
 testWidgets('priority badges remain visible beyond row limit and small later badges backfill',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:220,child:PackedBadges(maxRows:1,alwaysVisibleCount:2,children:[
   SizedBox(width:100,height:100),SizedBox(width:100,height:100),SizedBox(width:220,height:150),SizedBox(width:100,height:20),
  ]))))));
  final render=tester.renderObject<RenderPackedBadges>(find.byType(PackedBadges));
  expect(render.visible.length,2);expect(render.size.height,100);
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:220,child:PackedBadges(maxRows:2,children:[
   SizedBox(width:100,height:66),SizedBox(width:220,height:100),SizedBox(width:100,height:30),SizedBox(width:100,height:30),
  ]))))));
  final packed=tester.renderObject<RenderPackedBadges>(find.byType(PackedBadges));expect(packed.visible.length,3);expect(packed.size.height,66);
 });
 testWidgets('importance controls are hidden and detail editing preserves saved priority',(tester)async{
  await tester.pumpWidget(const MyApp(requireLogin:false));await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('quick-important')), findsNothing);
  elements.add('중요한 새 생각').important = true;
  await tester.pumpAndSettle();
  final context=tester.element(find.byKey(const ValueKey('quick-memo')));
  showElementMetadata(context,'중요한 새 생각');await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('detail-important')), findsNothing);
  expect(elements.records['중요한 새 생각']!.important,isTrue);
  await tester.tap(find.widgetWithText(FilledButton,'저장').last);await tester.pumpAndSettle();
  expect(elements.records['중요한 새 생각']!.important,isTrue);
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });
}
