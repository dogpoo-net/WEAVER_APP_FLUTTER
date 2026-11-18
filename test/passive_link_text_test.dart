import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/element_binding.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';
void main(){
 testWidgets('badge shows linked title styling without a link action',(tester)async{
  elements.clear();final record=elements.add('본문 문서 메모');
  record.inlineLinks.addAll([const ElementBinding('project:doc',3,5),const ElementBinding('label:memo',6,8)]);
  var taps=0;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:WordBadge(word:record.text,fullText:true,onTap:()=>taps++))));
  final rich=tester.widget<Text>(find.descendant(of:find.byType(WordBadge),matching:find.byWidgetPredicate((w)=>w is Text&&w.textSpan!=null)).first);
  final span=rich.textSpan! as TextSpan;expect(span.toPlainText(),record.text);
  final document=span.children![1] as TextSpan, memo=span.children![3] as TextSpan;
  expect(document.style!.color,const Color(0xFFFF9800));expect(memo.style!.decorationStyle,TextDecorationStyle.dotted);
  for(final child in span.children!.cast<TextSpan>()){expect(child.recognizer,isNull);expect(child.onEnter,isNull);}
  await tester.tap(find.byType(WordBadge));expect(taps,1);expect(find.byType(AlertDialog),findsNothing);
 });
 testWidgets('invalid binding ranges preserve plain text',(tester)async{
  late TextSpan span;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context){span=passiveLinkedText(context,'abc',[const ElementBinding('x',-1,2),const ElementBinding('x',1,99)]);return Text.rich(span);})));expect(span.toPlainText(),'abc');
 });
}
