import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
void main() {
 testWidgets('pending detail read opens only one dialog; resize click never opens detail; outside selection exits', (tester) async {
  tester.view.physicalSize=const Size(1200,900);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();
  final a=elements.add('첫 생각'),b=elements.add('둘째 생각');
  b.tags.add('독서');
  final layout=pageGraphLayout.blockLayout;
  layout.positions.addAll({a.id:const Offset(500,500),b.id:const Offset(800,500)});
  layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
  final card=find.byKey(ValueKey('canvas-thought-${a.id}'));
  await tester.tap(find.descendant(of:card,matching:find.byKey(const ValueKey('resize-right'))));await tester.pumpAndSettle();
  expect(find.byType(AlertDialog),findsNothing);
  final read=Completer<void>(); var requests=0;
  refreshWorkspaceForRead=(){requests++;return read.future;};addTearDown(()=>refreshWorkspaceForRead=null);
  final interaction=tester.widget<ThoughtInteraction>(card);
  interaction.onTap();interaction.onTap();expect(requests,1);
  read.complete();await tester.pumpAndSettle();expect(find.byKey(const ValueKey('element-editor')),findsOneWidget);
  final editor=find.byKey(const ValueKey('element-editor'));
  await tester.enterText(editor,'본문 #독자');await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);await tester.pump();
  expect(tester.widget<TextField>(editor).controller!.text,'본문 #독자');
  tester.testTextInput.updateEditingValue(const TextEditingValue(text:'본문 #독자\n',selection:TextSelection.collapsed(offset:7)));
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(editor).controller!.text.trim(),'본문');
  Navigator.of(tester.element(find.byKey(const ValueKey('element-editor')))).pop();await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));await tester.pumpAndSettle();
  await tester.tapAt(tester.getCenter(card));await tester.pumpAndSettle();
  expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'1');
  await tester.tapAt(tester.getCenter(find.byKey(ValueKey('canvas-thought-${b.id}'))));await tester.pumpAndSettle();
  expect(tester.widget<Checkbox>(find.byType(Checkbox)).value,false);
  expect(find.byType(AlertDialog),findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('mobile detail assist stays above the software keyboard and is tappable',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  tester.view.viewInsets=const FakeViewPadding(bottom:300);
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);addTearDown(tester.view.resetViewInsets);
  elements.clear();elements.add('본문');elements.add('후보').tags.add('독서');
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showElementMetadata(context,'본문'),child:const Text('열기'))))));
  await tester.tap(find.text('열기'));await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('element-editor')),'본문 #독');await tester.pumpAndSettle();
  final popup=find.byKey(const ValueKey('assist-popup'));expect(popup,findsOneWidget);
  expect(tester.getBottomLeft(popup).dy,lessThanOrEqualTo(544));
  await tester.tap(find.descendant(of:popup,matching:find.text('#독서')));await tester.pumpAndSettle();
  expect(tester.widget<TextField>(find.byKey(const ValueKey('element-editor'))).controller!.text.trim(),'본문');
  expect(find.text('#독서'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 for(final query in ['독','독서']) {
 testWidgets('unselected hashtag Enter preserves typed IME text ($query)',(tester)async{
  final c=TextEditingController(),f=FocusNode();String? chosen;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CaretAssist(controller:c,focus:f,words:const [],tags:const ['독서'],explicitSelectionOnly:true,onWord:(_){},onTag:(v)=>chosen=v,child:TextField(controller:c,focusNode:f)))));
  await tester.enterText(find.byType(TextField),'#$query');await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);await tester.pump();expect(chosen,isNull);expect(c.text,'#$query');
  c.value=TextEditingValue(text:'#$query',selection:TextSelection.collapsed(offset:query.length+1),composing:TextRange(start:query.length,end:query.length+1));await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);await tester.pump();expect(chosen,isNull);expect(c.text,'#$query');
  await tester.pumpWidget(const SizedBox());c.dispose();f.dispose();
 });
 }
}
