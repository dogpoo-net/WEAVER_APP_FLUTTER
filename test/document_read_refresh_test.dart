import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';
void main(){
 testWidgets('document reading refreshes every three seconds but editing and preview do not',(tester)async{
  refreshWorkspaceForRead=null;
  final p=WritingProject([],[],name:'문서')..document='이전 본문';var reads=0;
  await tester.pumpWidget(MaterialApp(home:ProjectPage(project:p,onReload:()async{reads++;p.document='서버 본문 $reads';})));
  await tester.pump(const Duration(seconds:3));await tester.pump();
  expect(reads,1);expect(find.text('서버 본문 1',findRichText:true),findsWidgets);
  await tester.tap(find.byTooltip('문서 수정'));await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('project-document')),'저장하지 않은 본문');
  await tester.pump(const Duration(seconds:6));await tester.pump();expect(reads,1);
  expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text,'저장하지 않은 본문');
  await tester.tap(find.byTooltip('미리보기'));await tester.pumpAndSettle();await tester.pump(const Duration(seconds:6));expect(reads,1);
  await tester.pumpWidget(const SizedBox());
 });
}
