import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_table.dart';
import 'package:weaver/features/inbox/document_markup.dart';
import 'package:weaver/features/inbox/document_line_numbers.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
void main(){
 testWidgets('tables render escaped pipes while alignment and code remain compatible',(tester)async{
  final text=tableMarkdown([['제목','열'],['a|b','줄1\n줄2']]);
  expect(tableCells(text.split('\n')[2])!.length,2);
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:DocumentMarkup(text:'$text\n| 오른쪽|\n<code>\n$text\n</code>'))));
  expect(find.byType(Table),findsOneWidget);
  expect(find.text('a|b',findRichText:true),findsOneWidget);
  expect(find.text('줄1\n줄2',findRichText:true),findsOneWidget);
  expect(tester.widget<RichText>(find.text('오른쪽',findRichText:true)).textAlign,TextAlign.right);
 });
 testWidgets('editor inserts a table, paints line gutter and saves source',(tester)async{
  final project=WritingProject([],[],name:'문서')..document='======문서======\n본문';
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project)));
  expect(find.byType(DocumentLineNumbers),findsOneWidget);
  final field=find.byKey(const ValueKey('project-document'));
  final controller=tester.widget<TextField>(field).controller!;
  controller.selection=TextSelection.collapsed(offset:controller.text.length);
  await tester.tap(find.text('표 삽입'));await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('table-cell-0-0')),'항목');
  await tester.enterText(find.byKey(const ValueKey('table-cell-1-0')),'내용');
  await tester.tap(find.text('삽입'));await tester.pumpAndSettle();
  expect(controller.text,contains('| 항목 |'));expect(controller.text,contains('| --- |'));
  await tester.tap(find.byTooltip('저장'));await tester.pumpAndSettle();expect(project.content,controller.text);
  await tester.tap(find.byTooltip('미리보기'));await tester.pumpAndSettle();expect(find.byType(Table),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
}
