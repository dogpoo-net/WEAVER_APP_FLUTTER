import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/admin_backoffice_page.dart';
import 'package:weaver/features/sync/workspace_deletion_dialog.dart';
void main(){
 testWidgets('admin exit returns to prior workspace without logging out',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(child:const Text('기존 워크스페이스'),onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>AdminBackofficePage(request:(action,body)async=>{'users':[]}))))))));
  await tester.tap(find.text('기존 워크스페이스'));await tester.pumpAndSettle();expect(find.text('관리자 백오피스'),findsOneWidget);
  await tester.tap(find.text('나가기'));await tester.pumpAndSettle();expect(find.text('기존 워크스페이스'),findsOneWidget);expect(find.text('관리자 백오피스'),findsNothing);
 });
 testWidgets('ordinary account admin denial shows error instead of data',(tester)async{
  await tester.pumpWidget(MaterialApp(home:AdminBackofficePage(request:(action,body)async=>throw StateError('관리자 권한이 필요합니다.'))));await tester.pumpAndSettle();expect(find.textContaining('관리자 권한이 필요합니다.'),findsOneWidget);expect(find.text('계정 권한'),findsNothing);
 });
 testWidgets('free used workspace clearly warns irreversible deletion',(tester)async{
  await tester.pumpWidget(MaterialApp(home:WorkspaceDeletionDialog(id:'w',request:(a,b)async=>{'requiresEmail':true,'retentionDays':0})));await tester.pumpAndSettle();expect(find.textContaining('즉시 영구 삭제'),findsOneWidget);expect(find.textContaining('30일간 보관'),findsNothing);
 });
 testWidgets('expired archived space exposes no enabled restore action',(tester)async{
  await tester.pumpWidget(MaterialApp(home:DeletedWorkspacesDialog(request:(a,b)async=>{'workspaces':[{'workspaceId':'w','name':'Archived','purgeAfter':'2026-12-01T00:00:00Z','canRestore':false}]},onRestored:()async{})));await tester.pumpAndSettle();final button=tester.widget<TextButton>(find.widgetWithText(TextButton,'유료 구독 필요'));expect(button.onPressed,isNull);
 });
}
