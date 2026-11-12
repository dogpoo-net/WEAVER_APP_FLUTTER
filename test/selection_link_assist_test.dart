import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/capture/capture_models.dart';

void main() {
 setUp(elements.clear);
 testWidgets('selected words retain alias while filter searches memo and document bodies', (tester) async {
  tester.view.physicalSize=const Size(1200,800);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final memo=elements.add('본문에서 찾는 바나나')..indexLabel='메모 제목';
  final doc=WritingProject([],[],name:'문서 제목')..document='======문서 제목======\n사과 내용';elements.indexProject(doc);
  final c=LabelTextController('선택한 글자'),focus=FocusNode();
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:CaretAssist(controller:c,focus:focus,words:labelAssistTargets(),onWord:c.insertTarget,useThoughtLabels:true,selectionAssist:true,showWhenEmpty:false,child:TextField(controller:c,focusNode:focus)))));
  focus.requestFocus();c.selection=const TextSelection(baseOffset:0,extentOffset:6);await tester.pumpAndSettle();
  final filter=find.byKey(const ValueKey('selection-link-filter'));expect(filter,findsOneWidget);
  expect(find.byKey(ValueKey('suggestion-${memo.text}')),findsOneWidget);
  expect(find.byKey(ValueKey('suggestion-project:${doc.id}')),findsOneWidget);
  await tester.enterText(filter,'없는 검색');await tester.pumpAndSettle();expect(filter,findsOneWidget);expect(find.text('검색 결과가 없습니다.'),findsOneWidget);
  await tester.enterText(filter,'바나나');await tester.pumpAndSettle();
  expect(find.byKey(ValueKey('suggestion-project:${doc.id}')),findsNothing);
  await tester.tap(find.byKey(ValueKey('suggestion-${memo.text}')));await tester.pumpAndSettle();
  expect(c.text,'선택한 글자');expect(c.bindings.single.id,'label:${memo.id}');
  focus.requestFocus();c.selection=const TextSelection(baseOffset:6,extentOffset:0);await tester.pumpAndSettle();
  await tester.enterText(filter,'사과');await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('suggestion-project:${doc.id}')));await tester.pumpAndSettle();
  expect(c.text,'선택한 글자');expect(c.bindings.single.id,'project:${doc.id}');
  await tester.pumpWidget(const SizedBox());c.dispose();focus.dispose();
 });
 testWidgets('link styles are normal weight with distinct decorations', (tester) async {
  final memo=elements.add('메모');
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context){
   final doc=inlineLinkStyle(context,'project:document');
   expect(doc.color,const Color(0xFFFF9800));expect(doc.decoration,TextDecoration.none);
   expect(inlineLinkStyle(context,'project:document',hovered:true).decoration,TextDecoration.underline);
   final linkedMemo=inlineLinkStyle(context,'label:${memo.id}');expect(linkedMemo.decorationStyle,TextDecorationStyle.dotted);expect(linkedMemo.fontWeight,FontWeight.normal);
   return const SizedBox();
  })));
 });
 testWidgets('single line badges never wrap a long or multiline memo', (tester) async {
  elements.add('긴 메모\n다음 줄').location = ThoughtLocation(37,127,1,DateTime(2026));
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:90,child:WordBadge(word:'긴 메모\n다음 줄',fullText:true,singleLine:true,onTap:(){})))));
  final label=tester.widget<Text>(find.byWidgetPredicate((w)=>w is Text && w.textSpan!=null));expect(label.maxLines,1);expect(label.softWrap,false);expect(label.textSpan!.toPlainText(),'긴 메모 다음 줄');
  expect(tester.takeException(),isNull);
 });
}
