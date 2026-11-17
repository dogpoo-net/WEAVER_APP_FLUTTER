import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/workspace_picker.dart';
void main(){
 testWidgets('groups ownership and shows actions by role', (tester)async{
 await tester.pumpWidget(MaterialApp(home:Scaffold(body:WorkspacePicker(
   workspaces:const[{'workspaceId':'a','name':'내 공간','role':'owner'},{'workspaceId':'b','name':'공유 공간','role':'editor'}],selected:'a',
   request:(_,_)async=>{},onCatalog:(_){}))));
 expect(find.text('소유한 워크스페이스'),findsOneWidget);expect(find.text('참여 중인 워크스페이스'),findsOneWidget);
 expect(find.byType(Divider),findsOneWidget);
 await tester.tap(find.byTooltip('워크스페이스 관리').first);await tester.pumpAndSettle();
 expect(find.text('이름변경'),findsOneWidget);expect(find.text('삭제'),findsOneWidget);expect(find.text('나가기'),findsNothing);
 await tester.tapAt(const Offset(5,5));await tester.pumpAndSettle();
 await tester.tap(find.byTooltip('워크스페이스 관리').last);await tester.pumpAndSettle();
 expect(find.text('나가기'),findsOneWidget);expect(find.text('삭제'),findsNothing);
 });
 testWidgets('member management receives the clicked workspace, not the active one',(tester)async{
 Map? managed;
 await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(child:const Text('열기'),onPressed:()=>showDialog<void>(context:context,builder:(_)=>WorkspacePicker(
 workspaces:const[{'workspaceId':'other','name':'다른 공간','role':'editor'}],selected:'active',request:(_,_)async=>{},onCatalog:(_){},onManageMembers:(row)async{managed=row;},
 )))))));
 await tester.tap(find.text('열기'));await tester.pumpAndSettle();
 await tester.tap(find.byTooltip('워크스페이스 관리'));await tester.pumpAndSettle();
 await tester.tap(find.text('멤버 관리'));await tester.pumpAndSettle();
 expect(managed?['workspaceId'],'other');expect(find.byType(WorkspacePicker),findsNothing);
 });
 testWidgets('create opens new workspace after catalog reload', (tester)async{
 String? selected;final calls=<String>[];
 await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(child:const Text('열기'),onPressed:()async{
 selected=await showDialog<String>(context:context,builder:(_)=>WorkspacePicker(workspaces:const[],selected:null,onCatalog:(_){},request:(action,body)async{
 calls.add(action);if(action=='create-workspace'){expect(body['name'],'새 공간');return {'workspaceId':'new'};}
 return {'workspaces':[{'workspaceId':'new','name':'새 공간','role':'owner'}],'defaultWorkspaceId':'new'};
 }));
 })))));
 await tester.tap(find.text('열기'));await tester.pumpAndSettle();
 await tester.tap(find.byTooltip('워크스페이스 추가'));await tester.pumpAndSettle();
 await tester.enterText(find.byType(TextField),'새 공간');await tester.tap(find.text('저장'));await tester.pumpAndSettle();
 await tester.pump(const Duration(milliseconds:500));expect(selected,'new');expect(calls,['create-workspace','catalog']);
 });
}
