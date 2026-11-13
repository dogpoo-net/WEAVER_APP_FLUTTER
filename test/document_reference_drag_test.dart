import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/word_badge.dart';
void main(){
 for(final mobile in [false,true]){
 testWidgets('reference drag opens a title dialog without replacing nearby prose (mobile=$mobile)',(tester)async{
  tester.view.physicalSize=mobile?const Size(390,844):const Size(1200,900);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  elements.clear();final memo=elements.add('가져올 메모')..indexLabel='검색 라벨';
  final other=WritingProject([],[],name:'참고 문서')..document='======참고 문서======\n검색 본문';
  final project=WritingProject([],[],name:'작성 문서')..document='기존 문장 그대로';
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project,projects:[project,other])));await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('project-document-reference-search')),mobile?findsNothing:findsOneWidget);
  final field=find.byKey(const ValueKey('project-document'));final c=tester.widget<TextField>(field).controller! as LabelTextController;
  for(final key in [memo.text,'project:${other.id}']){
    final source=find.byWidgetPredicate((widget)=>widget is WordBadge && widget.word==key).first;
    final original=c.text;final gesture=await tester.startGesture(tester.getCenter(source));
    if(mobile)await tester.pump(const Duration(milliseconds:600));
    await gesture.moveTo(tester.getCenter(field));await tester.pump();await gesture.up();await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-title-input')),findsOneWidget);expect(c.text,original);
    await tester.enterText(find.byKey(const ValueKey('link-title-input')),key==memo.text?'내 메모 링크':'');
    await tester.tap(find.text('확인'));await tester.pumpAndSettle();
    final link=c.bindings.firstWhere((link)=>link.id==(key==memo.text?'label:${memo.id}':'project:${other.id}'));
    expect(c.text.substring(0,link.start)+c.text.substring(link.end),original);
    expect(c.text.substring(link.start,link.end),key==memo.text?'내 메모 링크':'참고 문서');
  }
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());elements.clear();
 });}
}
