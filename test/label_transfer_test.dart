import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
 for(final left in [true,false]) {
 testWidgets('hold label transfers to closest edge left=$left',(tester)async{
  elements.clear();memoBoxes.clear();memoBoxFolders.clear();memoBoxFolderParents.clear();pageGraphLayout=GraphLayout();
  final source=elements.add('원본 #보존')..indexLabel='옮길 라벨'..indexLabelColor=0xFFFFCC80;
  final target=elements.add('대상 #유지');
  final layout=pageGraphLayout.blockLayout;
  layout.positions.addAll({source.id:const Offset(640,400),target.id:const Offset(940,400)});
  layout.layers.addAll([source.id,target.id]);
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));
  await tester.pumpAndSettle();
  final rect=tester.getRect(find.byKey(ValueKey('canvas-thought-${target.id}')));
  final label=find.byKey(ValueKey('thought-label-${source.id}'));
  final gesture=await tester.startGesture(tester.getCenter(label));
  await tester.pump(const Duration(milliseconds:650));
  await gesture.moveTo(Offset(left?rect.left+10:rect.right-10,rect.center.dy));
  await tester.pump();
  await gesture.up();await tester.pumpAndSettle();
  expect(source.indexLabel,isEmpty);expect(target.indexLabel,'옮길 라벨');
  expect(target.labelOnLeft,left);expect(target.indexLabelColor,0xFFFFCC80);
  expect(source.tags,contains('보존'));expect(target.tags,contains('유지'));
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
 }
}
