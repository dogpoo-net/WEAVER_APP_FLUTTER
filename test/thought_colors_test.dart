import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/thought_colors.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/element_store.dart';
void main(){
 for(final brightness in Brightness.values){
 testWidgets('20 palette swatches match rendered thought colors in $brightness',(tester)async{
  elements.clear();final record=elements.add('색상');late BuildContext page;
  await tester.pumpWidget(MaterialApp(theme:ThemeData(brightness:brightness),home:Builder(builder:(context){page=context;return Scaffold(body:TextButton(onPressed:()=>pickThoughtColor(context,null),child:const Text('색상 선택')));} )));
  await tester.tap(find.text('색상 선택'));await tester.pumpAndSettle();
  expect(thoughtPalette.length,20);expect(thoughtPalette.toSet().length,20);
  for(var i=0;i<20;i++){
   record.labelColor=thoughtPalette[i].toARGB32();
   final button=tester.widget<IconButton>(find.byKey(ValueKey('thought-color-$i')));
   final color=((button.icon as Container).decoration as BoxDecoration).color;
   expect(color,wordBackgroundColor(page,record.text));
  }
  await tester.tap(find.text('취소'));await tester.pumpAndSettle();await tester.pumpWidget(const SizedBox());elements.clear();
 });
 }
}
