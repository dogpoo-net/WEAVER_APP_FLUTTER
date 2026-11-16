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
 for(final direction in TextDirection.values){
 testWidgets('wide short badges fill beside tall ones across earlier column cuts ($direction)',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Directionality(textDirection:direction,child:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:220,child:PackedBadges(children:[
   const SizedBox(key:ValueKey('tall'),width:100,height:100),
   const SizedBox(key:ValueKey('narrow'),width:50,height:20),
   for(var i=0;i<3;i++)SizedBox(key:ValueKey('short-$i'),width:100,height:20),
   const SizedBox(key:ValueKey('wide'),width:212,height:30),
   const SizedBox(key:ValueKey('backfill'),width:50,height:20),
  ])))))));
  final tall=tester.getRect(find.byKey(const ValueKey('tall')));
  for(var i=0;i<3;i++){
   final rect=tester.getRect(find.byKey(ValueKey('short-$i')));
   expect(rect.top,tall.top+26*(i+1));expect(rect.bottom,lessThanOrEqualTo(tall.bottom));
  }
  final backfill=tester.getRect(find.byKey(const ValueKey('backfill')));expect(backfill.top,tall.top);
  final rects=[for(final key in ['tall','narrow','short-0','short-1','short-2','wide','backfill'])tester.getRect(find.byKey(ValueKey(key)))];
  for(var i=0;i<rects.length;i++){for(var j=i+1;j<rects.length;j++){expect(rects[i].overlaps(rects[j]),isFalse);}}
  expect(tester.getSize(find.byType(PackedBadges)).height,136);
 });
 }
 testWidgets('mixed sizes remain in bounds without overlap after resizing',(tester)async{
  var width=420.0;late StateSetter update;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:StatefulBuilder(builder:(context,set){update=set;return Align(alignment:Alignment.topLeft,child:SizedBox(width:width,child:PackedBadges(children:[
   for(var i=0;i<120;i++)SizedBox(key:ValueKey('mixed-$i'),width:40.0+(i*43)%260,height:20.0+(i*17)%91),
  ])));})))));
  void check(){
   final bounds=tester.getRect(find.byType(PackedBadges));
   final rects=[for(var i=0;i<120;i++)tester.getRect(find.byKey(ValueKey('mixed-$i')))];
   for(var i=0;i<rects.length;i++){
    expect(rects[i].left,greaterThanOrEqualTo(bounds.left-.01));expect(rects[i].right,lessThanOrEqualTo(bounds.right+.01));
    for(var j=i+1;j<rects.length;j++){expect(rects[i].overlaps(rects[j]),isFalse);}
   }
   expect(tester.takeException(),isNull);
  }
  check();update(()=>width=300);await tester.pump();check();
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
