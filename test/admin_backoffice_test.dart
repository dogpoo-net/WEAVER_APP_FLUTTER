import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/admin_backoffice_page.dart';
import 'package:weaver/features/sync/workspace_deletion_dialog.dart';
void main(){
 testWidgets('account search assists by name below input without a dialog',(tester)async{
  final queries=<String>[];
  await tester.pumpWidget(MaterialApp(home:AdminBackofficePage(request:(action,body)async{
    if(action=='admin/users'){queries.add(body['query'] as String);return {'users':[{'id':'u','name':'캔디','email':'candy@example.com','platformRole':'user'}]};}
    return {'account':{'id':'u','name':'캔디','email':'candy@example.com','platformRole':'user'},'accountPolicy':{'plan':{'code':'free'}},'workspaces':[]};
  })));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField,'이메일 또는 이름 검색'),'디');await tester.pump(const Duration(milliseconds:300));await tester.pumpAndSettle();
  expect(queries.last,'디');expect(find.byType(AlertDialog),findsNothing);
  final option=find.byKey(const ValueKey('suggestion-캔디 · candy@example.com'));expect(option,findsOneWidget);
  expect(tester.getTopLeft(option).dy,greaterThan(tester.getBottomLeft(find.byType(TextField)).dy));
  await tester.tap(option);await tester.pumpAndSettle();expect(find.text('계정 권한'),findsOneWidget);
 });
 testWidgets('admin exit returns to prior workspace without logging out',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(child:const Text('기존 워크스페이스'),onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>AdminBackofficePage(request:(action,body)async=>{'users':[]}))))))));
  await tester.tap(find.text('기존 워크스페이스'));await tester.pumpAndSettle();expect(find.text('관리자 백오피스'),findsOneWidget);
  await tester.tap(find.text('나가기'));await tester.pumpAndSettle();expect(find.text('기존 워크스페이스'),findsOneWidget);expect(find.text('관리자 백오피스'),findsNothing);
 });
 testWidgets('ordinary account admin denial shows error instead of data',(tester)async{
  await tester.pumpWidget(MaterialApp(home:AdminBackofficePage(request:(action,body)async=>throw StateError('관리자 권한이 필요합니다.'))));await tester.pumpAndSettle();expect(find.textContaining('관리자 권한이 필요합니다.'),findsOneWidget);expect(find.text('계정 권한'),findsNothing);
 });
 testWidgets('free used workspace shows retention and paid restoration',(tester)async{
  await tester.pumpWidget(MaterialApp(home:WorkspaceDeletionDialog(id:'w',request:(a,b)async=>{'requiresEmail':true,'retentionDays':30})));await tester.pumpAndSettle();expect(find.textContaining('30일간 보관'),findsOneWidget);expect(find.textContaining('유료 구독'),findsOneWidget);
 });
 testWidgets('expired archived space exposes no enabled restore action',(tester)async{
  await tester.pumpWidget(MaterialApp(home:DeletedWorkspacesDialog(request:(a,b)async=>{'workspaces':[{'workspaceId':'w','name':'Archived','purgeAfter':'2026-12-01T00:00:00Z','canRestore':false}]},onRestored:()async{})));await tester.pumpAndSettle();final button=tester.widget<TextButton>(find.widgetWithText(TextButton,'유료 구독 필요'));expect(button.onPressed,isNull);
 });
}
