import 'package:weaver/features/inbox/thought_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
 test('label chooses largest overlap rather than pointer or inflated bounds',(){
   final candidates=[(id:'upper',bounds:const Rect.fromLTWH(0,0,200,80)),(id:'source',bounds:const Rect.fromLTWH(0,80,200,80))];
   expect(labelOverlapTarget(const Rect.fromLTWH(40,60,80,24),candidates),'upper');
   expect(labelOverlapTarget(const Rect.fromLTWH(40,78,80,24),candidates),'source');
   expect(labelOverlapTarget(const Rect.fromLTWH(205,50,80,24),candidates),isNull);
 });
 test('equal overlap favors frontmost memo',(){
   expect(labelOverlapTarget(const Rect.fromLTWH(40,40,80,24),[
     (id:'back',bounds:const Rect.fromLTWH(0,0,200,100)),
     (id:'front',bounds:const Rect.fromLTWH(0,32,200,100)),
   ]),'front');
 });

 for(final blocks in [true,false]) {
 for(final destination in ['empty','self','occupied']) {
 for(final left in [true,false]) {
 testWidgets('hold label transfers to closest edge blocks=$blocks destination=$destination left=$left',(tester)async{
  elements.clear();memoBoxes.clear();memoBoxFolders.clear();memoBoxFolderParents.clear();pageGraphLayout=GraphLayout();
  final source=elements.add('원본 #보존')..indexLabel='옮길 라벨'..indexLabelColor=0xFFFFCC80;
  source.labelOnLeft=!left;
  final target=destination=='self'?source:elements.add('대상 #유지');
  if(destination=='occupied')target.indexLabel='기존 라벨';
  final other=elements.add('다른 메모')..indexLabel='다른 라벨';
  final layout=blocks?pageGraphLayout.blockLayout:pageGraphLayout;
  layout.positions.addAll({source.id:const Offset(640,400),if(target!=source)target.id:const Offset(940,400),other.id:const Offset(640,550)});
  layout.layers.addAll({source.id,target.id,other.id});
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){})));
  await tester.pumpAndSettle();
  final rect=tester.getRect(find.byKey(ValueKey('canvas-thought-${target.id}')));
  final label=find.byKey(ValueKey('thought-label-${source.id}'));
  final gesture=await tester.startGesture(tester.getCenter(label));
  await tester.pump(const Duration(milliseconds:650));
  await gesture.moveTo(Offset(left?rect.left+10:rect.right-10,rect.center.dy));
  await tester.pump();
  await gesture.up();await tester.pumpAndSettle();
  if(destination=='occupied'){
   expect(source.indexLabel,'옮길 라벨');expect(target.indexLabel,'기존 라벨');
   expect(find.text('이미 라벨이 있는 메모입니다. 기존 라벨을 옮기거나 지운 뒤 다시 시도해주세요.'),findsOneWidget);
  }else{
  if(target!=source)expect(source.indexLabel,isEmpty);expect(target.indexLabel,'옮길 라벨');
  expect(target.labelOnLeft,left);expect(target.indexLabelColor,0xFFFFCC80);
  expect(source.tags,contains('보존'));if(target!=source)expect(target.tags,contains('유지'));
  }
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
 }
 }
 }
}
