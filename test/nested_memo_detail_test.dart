import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/label_links.dart';
void main(){testWidgets('linked memo opens above the original unsaved detail',(tester)async{
 elements.clear();elements.add('원본');final linked=elements.add('연결된 생각');
 await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showElementMetadata(context,'원본'),child:const Text('열기'))))));
 await tester.tap(find.text('열기'));await tester.pumpAndSettle();
 final editor=find.byKey(const ValueKey('element-editor'));
 await tester.enterText(editor,'저장 전 내용');await tester.pumpAndSettle();
 final original=tester.widget<TextField>(editor).controller!;
 openInlineLink(tester.element(editor),'label:${linked.id}');await tester.pumpAndSettle();
 expect(find.byType(AlertDialog,skipOffstage:false),findsNWidgets(2));
 expect(tester.widget<TextField>(editor.last).controller!.text,'연결된 생각');
 Navigator.of(tester.element(editor.last)).pop();await tester.pumpAndSettle();
 expect(tester.widget<TextField>(editor).controller,same(original));expect(original.text,'저장 전 내용');
 await tester.pumpWidget(const SizedBox());
});}
