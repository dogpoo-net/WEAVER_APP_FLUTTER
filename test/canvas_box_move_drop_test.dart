import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){
 for(final scenario in [(false,250.0),(true,250.0),(true,40.0)]){
 final (lifted,distance)=scenario;
 final rejected=lifted&&distance==250;
 testWidgets('folder drop rules apply only to lifted memo: $lifted distance=$distance',(tester)async{
  tester.view.physicalSize=const Size(1400,1000);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  elements.clear();memoBoxes.clear();memoBoxFolders.clear();memoBoxFolderParents.clear();pageGraphLayout=GraphLayout();
  final a=elements.add('이동'),b=elements.add('아래 상자');
  final owner=MemoBox('위 상자',ids:[a.id],folder:'폴더');memoBoxes.addAll([owner,MemoBox('아래 상자',ids:[b.id],folder:'폴더')]);memoBoxFolders.add('폴더');
  final layout=pageGraphLayout.blockLayout;
  layout.positions.addAll({a.id:const Offset(500,500),b.id:const Offset(500,1000)});
  layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
  final finder=find.byKey(ValueKey('canvas-thought-${a.id}'));
  final node=tester.widget<ThoughtInteraction>(finder);
  final start=layout.positions[a.id]!;
  final pointer=tester.getCenter(finder)+Offset(0,distance);
  if(lifted)node.onLift!();node.onActiveChanged!(true);
  node.onMove(Offset(0,distance));
  // Pointer-up can precede the next frame; the old region closure is still installed.
  node.onDrop(pointer);node.onActiveChanged!(false);node.onEnd();await tester.pumpAndSettle();
  expect(owner.elementIds,contains(a.id));
  expect(layout.positions[a.id],rejected?start:start+Offset(0,distance));
  expect(find.text('생각은 메모상자 안에 담아주세요. 폴더에는 직접 넣을 수 없습니다.'),rejected?findsOneWidget:findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
 }
}
