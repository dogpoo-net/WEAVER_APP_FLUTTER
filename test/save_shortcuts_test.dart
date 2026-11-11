import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
Future<void> saveKey(WidgetTester tester)async{await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);await tester.sendKeyEvent(LogicalKeyboardKey.keyS);await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);await tester.pumpAndSettle();}
void main(){
 testWidgets('Project Ctrl+S saves and reports completion', (tester)async{
  final project=WritingProject([],[],name:'test')..document='before';var saves=0;
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project,onSave:()async{saves++;})));
  await tester.enterText(find.byKey(const ValueKey('project-document')),'after');await saveKey(tester);
  expect(project.document,'after');expect(saves,1);expect(find.text('저장되었습니다.'),findsOneWidget);
 });
 for(final blocks in [false,true]){
  testWidgets('Canvas save and overview menu ($blocks)',(tester)async{
   elements.clear();var saves=0;
   await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){},onSave:()async{saves++;})));
   await tester.pumpAndSettle();expect(find.byTooltip('전체 위치 보기'),findsNothing);
   await tester.tap(find.byTooltip('저장 (Ctrl+S)'));await tester.pumpAndSettle();expect(saves,1);expect(find.text('저장되었습니다.'),findsOneWidget);
   await saveKey(tester);expect(saves,2);
   await tester.tap(find.byTooltip('배치 초기화'));await tester.pumpAndSettle();expect(find.text('전체 보기'),findsOneWidget);
   expect(tester.getTopLeft(find.text('전체 보기')).dy,lessThan(tester.getTopLeft(find.text('펼쳐보기')).dy));
  });
 }
}
