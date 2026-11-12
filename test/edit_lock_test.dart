import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/edit_lock.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
void main(){
 test('Confirmation uses explicit paragraphs and word-only break opportunities',(){expect(takeoverMessage.split('\n').length,3);expect(wordWrapped(takeoverMessage).replaceAll('\u2060',''),takeoverMessage);expect(wordWrapped('현재 편집중입니다.'),'현\u2060재 편\u2060집\u2060중\u2060입\u2060니\u2060다\u2060.');});
 testWidgets('takeover requires confirmation and server status immediately removes editing permission',(tester)async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());int takeovers=0;
  storage.documentLease=(id,token,release)async=>{'acquired':false,'holder':'다른 기기'};
  storage.takeLease=(id,token)async{takeovers++;return {'acquired':true};};
  final lock=EditLock('canvas:diagram',storage);await tester.pump();
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>ListenableBuilder(listenable:lock,builder:(_,child)=>IconButton(tooltip:'잠금',icon:Icon(lock.granted?Icons.lock_open:Icons.lock_outline),onPressed:()=>lock.takeOver(context)))))));
  expect(find.byIcon(Icons.lock_outline),findsOneWidget);await tester.tap(find.byTooltip('잠금'));await tester.pumpAndSettle();expect(find.bySemanticsLabel(takeoverMessage),findsOneWidget);expect(takeovers,0);
  await tester.tap(find.text('취소'));await tester.pumpAndSettle();expect(takeovers,0);
  await tester.tap(find.byTooltip('잠금'));await tester.pumpAndSettle();await tester.tap(find.text('잠금 해제'));await tester.pumpAndSettle();expect(takeovers,1);expect(find.byIcon(Icons.lock_open),findsOneWidget);
  storage.leaseStates['canvas:diagram']={'acquired':false};storage.leaseChanges.value++;await tester.pump();expect(find.byIcon(Icons.lock_outline),findsOneWidget);
  await tester.pumpWidget(const SizedBox());lock.dispose();await tester.pump();
 });
}
