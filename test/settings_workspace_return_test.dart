import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/thought_settings.dart';

void main(){
 testWidgets('current workspace selection returns to same settings dialog',(tester)async{
 await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
   child:const Text('열기'),onPressed:()=>showThoughtSettings(context,null,onWorkspaces:()async{
     await showDialog<void>(context:context,builder:(context)=>SimpleDialog(title:const Text('워크스페이스 선택'),children:[
       SimpleDialogOption(onPressed:()=>Navigator.pop(context),child:const Text('현재 공간')),
     ]));
   }),
 )))));
 await tester.tap(find.text('열기'));await tester.pumpAndSettle();
 final settings=tester.element(find.text('설정'));
 await tester.tap(find.text('워크스페이스'));await tester.pumpAndSettle();
 await tester.tap(find.text('현재 공간'));await tester.pumpAndSettle();
 expect(tester.element(find.text('설정')),same(settings));
 expect(find.byType(LinearProgressIndicator),findsNothing);
 await tester.tap(find.byKey(const ValueKey('close-settings')));await tester.pumpAndSettle();
 expect(find.text('설정'),findsNothing);
 });
}
