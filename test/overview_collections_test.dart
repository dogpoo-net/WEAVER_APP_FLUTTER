import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/overview_collections.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/capture/capture_models.dart';
void main(){
 setUp((){elements.clear();SharedPreferences.setMockInitialValues({});});
 testWidgets('Documents filter title/body and show author and modification time',(tester)async{
  final p=WritingProject([],[],name:'문서')..document='======계획======\n검색용 본문';final note=Note(p.content,created:DateTime(2026,1,1))..project=p;
  final storage=WorkspaceStorage(await SharedPreferences.getInstance());storage.itemMetadata=(_,id)=>{'author':'김작성','updatedAt':'2026-11-12T01:00:00Z'};
  await tester.pumpWidget(MaterialApp(home:AllThoughtsPage(notes:[note],storage:storage,initialView:ThoughtView.documents)));await tester.pumpAndSettle();expect(find.text('계획'),findsOneWidget);expect(find.textContaining('김작성'),findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('documents-search')),'검색용');await tester.pump();expect(find.text('계획'),findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('documents-search')),'없는 검색어');await tester.pump();expect(find.text('일치하는 문서가 없습니다.'),findsOneWidget);
 });
 testWidgets('Document opens as a reader and takes a lease only when editing',(tester)async{
  var leases=0;final p=WritingProject([],[],name:'문서')..document='======열람======\n읽는 본문';
  await tester.pumpWidget(MaterialApp(home:ProjectPage(project:p,onLease:(_,token,release)async{if(!release)leases++;return {'acquired':true};})));await tester.pumpAndSettle();expect(find.byType(ProjectDocumentEditor),findsNothing);expect(leases,0);
  await tester.tap(find.byTooltip('문서 수정'));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('project-document')),findsOneWidget);expect(leases,1);await tester.pumpWidget(const SizedBox());
 });
 testWidgets('Narrow tabs scroll to audio; view options and owner thought are available',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final r=elements.add('목소리를 남긴 생각')..recordings.add(const VoiceAttachment('clip',12500));
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[])));await tester.pumpAndSettle();
  final tabs=find.byKey(const PageStorageKey('overview-tabs'));expect(tester.widget<SingleChildScrollView>(tabs).scrollDirection,Axis.horizontal);await tester.drag(tabs,const Offset(-400,0));await tester.pumpAndSettle();await tester.tap(find.text('음성'));await tester.pumpAndSettle();expect(find.byType(AttachmentCollection),findsOneWidget);expect(find.text('0:13'),findsOneWidget);
  await tester.tap(find.byTooltip('정렬'));await tester.pumpAndSettle();await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>,'자세히'));await tester.pumpAndSettle();expect(find.text(r.text),findsOneWidget);await tester.tap(find.byKey(const ValueKey('attachment-clip')));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('element-editor')),findsOneWidget);expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });
}
