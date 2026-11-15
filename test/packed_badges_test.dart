import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/packed_badges.dart';
import 'package:weaver/features/inbox/word_badge.dart';
void main(){
 testWidgets('short badges stack alongside a taller badge without overlap',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:220,child:PackedBadges(children:[
   SizedBox(key:ValueKey('tall'),width:100,height:66),SizedBox(key:ValueKey('one'),width:100,height:30),SizedBox(key:ValueKey('two'),width:100,height:30),SizedBox(key:ValueKey('wide'),width:212,height:30),SizedBox(key:ValueKey('last'),width:90,height:30),
  ]))))));
  final tall=tester.getRect(find.byKey(const ValueKey('tall'))),one=tester.getRect(find.byKey(const ValueKey('one'))),two=tester.getRect(find.byKey(const ValueKey('two')));
  expect(one.left,tall.right+6);expect(two.left,one.left);expect(two.top,one.bottom+6);expect(two.bottom,tall.bottom);
  final rects=[for(final key in ['tall','one','two','wide','last'])tester.getRect(find.byKey(ValueKey(key)))];
  for(var i=0;i<rects.length;i++){for(var j=i+1;j<rects.length;j++){expect(rects[i].overlaps(rects[j]),isFalse);}}
 });
 testWidgets('multiline full badges retain newlines and grow vertically',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Column(children:[WordBadge(word:'첫 줄\n둘째 줄',fullText:true,onTap:(){}),WordBadge(word:'한 줄',fullText:true,onTap:(){})]))));
  expect(tester.getSize(find.byType(WordBadge).first).height,greaterThan(tester.getSize(find.byType(WordBadge).last).height));
  final text=tester.widgetList<Text>(find.byType(Text)).where((t)=>t.textSpan?.toPlainText()=='첫 줄\n둘째 줄').single;
  expect(text.maxLines,isNull);expect(text.softWrap,isTrue);
 });
 testWidgets('more expands the packed height and restores hidden semantics',(tester)async{
  var rows=2;bool? overflow;late StateSetter update;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(c,set){update=set;return Align(alignment:Alignment.topLeft,child:SizedBox(width:110,child:PackedBadges(maxRows:rows,onOverflowChanged:(v)=>overflow=v,children:[for(var i=0;i<5;i++)SizedBox(width:100,height:30,child:Text('메모 $i'))])));}))));
  await tester.pump();expect(overflow,isTrue);expect(tester.getSize(find.byType(PackedBadges)).height,66);
  update(()=>rows=5);await tester.pump();await tester.pump();expect(overflow,isFalse);expect(tester.getSize(find.byType(PackedBadges)).height,174);
 });
}
