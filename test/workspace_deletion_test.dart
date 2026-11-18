import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/workspace_deletion_dialog.dart';
void main(){
 for(final used in [false,true]){
 testWidgets('deletion requires email only for used spaces: $used',(tester)async{
 final calls=<String>[];Map<String,Object?>? deletion;bool? result;
 await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(child:const Text('열기'),onPressed:()async{
 result=await showDialog<bool>(context:context,builder:(_)=>WorkspaceDeletionDialog(id:'w',request:(action,body)async{
 calls.add(action);if(action=='delete-workspace-preview')return {'requiresEmail':used,'retentionDays':used?30:0};
 if(action=='delete-workspace')deletion=body;return {};
 }));
 })))));
 await tester.tap(find.text('열기'));await tester.pumpAndSettle();
 expect(calls,['delete-workspace-preview']);
 if(used){
 expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'인증 후 삭제')).onPressed,isNull);
 expect(find.textContaining('30일'),findsOneWidget);
 await tester.tap(find.text('소유자 이메일로 인증메일 보내기'));await tester.pumpAndSettle();
 await tester.enterText(find.byType(TextField),'12345678');await tester.pump();await tester.tap(find.text('인증 후 삭제'));
 }else{expect(find.text('변경 이력이 없는 워크스페이스입니다. 삭제하시겠어요?'),findsOneWidget);expect(find.byType(TextField),findsNothing);await tester.tap(find.text('삭제'));}
 await tester.pumpAndSettle();expect(result,true);expect(deletion?['workspaceId'],'w');expect(deletion?['code'],used?'12345678':null);
 });}
 testWidgets('restore refreshes archived and active lists',(tester)async{
 var restored=false,refreshes=0;
 await tester.pumpWidget(MaterialApp(home:DeletedWorkspacesDialog(onRestored:()async{refreshes++;},request:(action,body)async{
 if(action=='restore-workspace'){expect(body['workspaceId'],'w');restored=true;return {};}
 return {'workspaces':restored?[]:[{'workspaceId':'w','name':'보관된 공간','purgeAfter':'2027-01-17T00:00:00Z'}]};
 })));
 await tester.pumpAndSettle();await tester.tap(find.text('복원'));await tester.pumpAndSettle();
 expect(refreshes,1);expect(find.text('복원할 워크스페이스가 없습니다.'),findsOneWidget);
 });
}
