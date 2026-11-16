import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
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
 testWidgets('Document editing does not acquire or release locks', (tester)async{
  final project=WritingProject([],[],name:'shared')..document='original';var calls=0;
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());
  storage.documentLease=(id,token,release)async{calls++;return {'acquired':false,'holder':'Other'};};
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project,storage:storage)));
  await tester.pumpAndSettle();expect(find.byKey(const ValueKey('project-document')),findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('project-document')),'edited');await saveKey(tester);expect(project.document,'edited');
  await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();expect(calls,0);
 });
 testWidgets('Background updates leave the active document and caret untouched',(tester)async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());final project=WritingProject([],[],name:'doc')..document='saved';
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project,storage:storage)));
  final finder=find.byKey(const ValueKey('project-document'));await tester.enterText(finder,'unsaved local');
  project.document='server latest';storage.liveChanges.value++;await tester.pump();
  final controller=tester.widget<TextField>(finder).controller!;expect(controller.text,'unsaved local');controller.selection=const TextSelection.collapsed(offset:3);
  storage.liveChanges.value++;await tester.pump();expect(controller.selection.baseOffset,3);await tester.pumpWidget(const SizedBox());
 });
 for(final blocks in [false,true]){
  testWidgets('Canvas save and overview menu ($blocks)',(tester)async{
   elements.clear();var saves=0;
   await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){},onSave:()async{saves++;})));
   await tester.pumpAndSettle();expect(find.byTooltip('전체 위치 보기'),findsNothing);
   await tester.tap(find.byTooltip('저장 (Ctrl+S)'));await tester.pumpAndSettle();expect(saves,1);expect(find.text('저장되었습니다.'),findsOneWidget);
   await saveKey(tester);expect(saves,2);
   await tester.tap(find.byTooltip('배치 초기화'));await tester.pumpAndSettle();expect(find.descendant(of:find.byType(PopupMenuItem<String>),matching:find.text('전체 보기')),findsOneWidget);
   expect(tester.getTopLeft(find.descendant(of:find.byType(PopupMenuItem<String>),matching:find.text('전체 보기'))).dy,lessThan(tester.getTopLeft(find.text('펼쳐보기')).dy));
  });
 }
}
