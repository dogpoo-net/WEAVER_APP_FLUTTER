import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/project_page.dart';
void main() {
 setUp(elements.clear);
 testWidgets('link title accepts alias, full memo fallback, cancel and markup bypass', (tester) async {
  final memo=elements.add('메모 본문 전체')..indexLabel='짧은 라벨';
  final c=LabelTextController();
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>insertAssistedLink(context,c,memo.text),child:const Text('추가'))))));
  await tester.tap(find.text('추가'));await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('link-title-input')),'별칭');
  await tester.tap(find.text('확인'));await tester.pumpAndSettle();expect(c.text,'별칭');expect(c.bindings.single.id,'label:${memo.id}');
  c.loadDocument('',[]);await tester.tap(find.text('추가'));await tester.pumpAndSettle();await tester.tap(find.text('확인'));await tester.pumpAndSettle();expect(c.text,memo.text);
  c.loadDocument('원문',[]);await tester.tap(find.text('추가'));await tester.pumpAndSettle();await tester.tap(find.text('취소'));await tester.pumpAndSettle();expect(c.text,'원문');expect(c.bindings,isEmpty);
  for(final text in ['[[표시|','[[짧은']) {c.loadDocument(text,[]);await tester.tap(find.text('추가'));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('link-title-input')),findsNothing);expect(c.text,text.contains('|')?'표시':'짧은 라벨');expect(c.bindings.single.id,'label:${memo.id}');}
  await tester.pumpWidget(const SizedBox());c.dispose();
 });
 testWidgets('empty document title replaces selection with document title', (tester) async {
  final doc=WritingProject([],[],name:'문서 제목');elements.indexProject(doc);
  final c=LabelTextController('선택')..selection=const TextSelection(baseOffset:0,extentOffset:2);
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>insertAssistedLink(context,c,'project:${doc.id}'),child:const Text('추가'))))));
  await tester.tap(find.text('추가'));await tester.pumpAndSettle();await tester.tap(find.text('확인'));await tester.pumpAndSettle();expect(c.text,doc.title);expect(c.bindings.single.id,'project:${doc.id}');
  await tester.pumpWidget(const SizedBox());c.dispose();
 });
}
