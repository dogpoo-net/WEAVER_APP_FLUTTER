import 'package:weaver/features/inbox/element_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/document_merge_dialog.dart';
import 'package:weaver/features/sync/document_merge.dart';
import 'document_merge_test.dart' show note;
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 testWidgets('draft persists without save, reopens and shows warning on reader and editor',(tester)async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'owner');
  final project=WritingProject([],[],name:'doc',id:'p')..document='saved';
  await storage.write(WorkspaceSnapshot.encode([Note('saved')..project=project]));
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project,storage:storage)));
  await tester.enterText(find.byKey(const ValueKey('project-document')),'local draft');await tester.pumpAndSettle();
  expect(storage.documentDraft('p')!['text'],'local draft');expect(storage.documentDraft('p')!['saved'],0);expect(project.document,'saved');expect(find.text('아직 저장되지 않았습니다.'),findsOneWidget);
  final form=tester.getRect(find.byKey(const ValueKey('project-document'))),notice=tester.getRect(find.text('아직 저장되지 않았습니다.'));
  expect(notice.center.dx,closeTo(form.center.dx,.1));expect(notice.left,greaterThanOrEqualTo(form.left));expect(notice.right,lessThanOrEqualTo(form.right));expect(notice.bottom,lessThan(form.bottom));
  await tester.pumpWidget(const SizedBox());await tester.pump();
  await tester.pumpWidget(MaterialApp(home:ProjectPage(project:project,storage:storage)));await tester.pumpAndSettle();
  expect(find.text('아직 저장되지 않았습니다.'),findsOneWidget);expect(find.text('local draft',findRichText:true),findsWidgets);
  await tester.tap(find.byTooltip('문서 수정'));await tester.pumpAndSettle();expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text,'local draft');
  await tester.tap(find.byTooltip('저장'));await tester.pumpAndSettle();expect(storage.documentDraft('p'),isNull);expect(find.text('아직 저장되지 않았습니다.'),findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('back asks before leaving unsaved work and discards the draft', (tester) async {
   final storage = WorkspaceStorage(await SharedPreferences.getInstance(), owner: 'owner');
   final project = WritingProject([], [], name: 'doc', id: 'p')..document = 'saved';
   addTearDown(() => elements.sources.remove(project));
   await tester.pumpWidget(MaterialApp(home: ProjectPage(project: project, storage: storage)));
   await tester.tap(find.byTooltip('문서 수정'));
   await tester.pumpAndSettle();
   await tester.enterText(find.byKey(const ValueKey('project-document')), 'draft');
   await tester.pumpAndSettle();
   await tester.pageBack();
   await tester.pumpAndSettle();
   expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNull);
   expect(find.text('저장하지 않은 자료가 있습니다. 정말 나갈까요?'), findsOneWidget);
   await tester.tap(find.text('취소'));
   await tester.pumpAndSettle();
   expect(find.byType(ProjectDocumentEditor), findsOneWidget);
   await tester.pageBack();
   await tester.pumpAndSettle();
   await tester.tap(find.text('나가기'));
   await tester.pumpAndSettle();
   expect(find.byType(ProjectDocumentEditor), findsNothing);
   expect(project.document, 'saved');
   expect(storage.documentDraft('p'), isNull);
 });
 testWidgets('failed server save retains unsaved flag',(tester)async{
  final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'owner');final project=WritingProject([],[],name:'doc',id:'p')..document='saved';
  await tester.pumpWidget(MaterialApp(home:ProjectDocumentEditor(project:project,storage:storage,onSave:()async{throw StateError('offline');})));
  await tester.enterText(find.byKey(const ValueKey('project-document')),'draft');await tester.tap(find.byTooltip('저장'));await tester.pumpAndSettle();
  expect(storage.documentDraft('p')!['saved'],0);expect(find.text('아직 저장되지 않았습니다.'),findsOneWidget);await tester.pumpWidget(const SizedBox());
 });
 testWidgets('manual conflict resolution can choose server content without dropping unrelated edits',(tester)async{
  final plan=mergeDocument(note('a\nb'),note('MINE\nb'),note('SERVER\nB'));Map<String,dynamic>? result;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{result=await resolveDocumentConflict(context,DocumentMergeConflict(plan,{}));},child:const Text('resolve'))))));
  await tester.tap(find.text('resolve'));await tester.pumpAndSettle();expect(find.textContaining('문서 충돌'),findsOneWidget);
  await tester.tap(find.text('서버 변경 사용'));await tester.pumpAndSettle();await tester.tap(find.text('병합 적용'));await tester.pumpAndSettle();
  expect(documentSegment(result!).text,'SERVER\nB');
 });
 test('drafts are isolated per account and saved flags remain explicit',()async{
  final prefs=await SharedPreferences.getInstance();final a=WorkspaceStorage(prefs,owner:'a'),b=WorkspaceStorage(prefs,owner:'b');
  await a.writeDocumentDraft('p',{'text':'private'});expect(b.documentDraft('p'),isNull);await a.writeDocumentDraft('p',null);expect(prefs.getString(a.scoped('document.draft.p')),'{"saved":1}');
 });
}
