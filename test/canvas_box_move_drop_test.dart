import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){
 testWidgets('ordinary pointer drops nest boxes and move thoughts into boxes', (tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  elements.clear();
  memoBoxes.clear();
  memoBoxFolders.clear();
  memoBoxFolderParents.clear();
  pageGraphLayout = GraphLayout();
  final parent = MemoBox('상위 상자');
  final child = MemoBox('하위 상자');
  final memo = elements.add('드래그할 생각');
  memoBoxes.addAll([parent, child]);
  final layout = pageGraphLayout.blockLayout;
  layout.containerBounds.addAll({
    'box:상위 상자': const Rect.fromLTWH(400, 300, 400, 350),
    'box:하위 상자': const Rect.fromLTWH(900, 300, 180, 180),
  });
  layout.positions[memo.id] = const Offset(900, 630);
  layout.viewport = Matrix4.identity().storage.toList();
  await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
  await tester.pumpAndSettle();

  final childHeader = find.byKey(const ValueKey('box-drag-header-하위 상자'));
  final parentHeader = find.byKey(const ValueKey('box-drag-header-상위 상자'));
  final insideParent = tester.getCenter(parentHeader) + const Offset(0, 110);
  final grab = tester.getCenter(childHeader);
  final drag = await tester.startGesture(grab);
  await drag.moveTo(Offset.lerp(grab, insideParent, .5)!);
  await tester.pump();
  await drag.moveTo(insideParent);
  await tester.pump();
  await drag.up();
  await tester.pumpAndSettle();
  expect(parentMemoBox(child), parent);

  final insideChild = tester.getCenter(childHeader) + const Offset(0, 65);
  final finder = find.byKey(ValueKey('canvas-thought-${memo.id}'));
  final node = tester.widget<ThoughtInteraction>(finder);
  node.onActiveChanged!(true);
  node.onMove(insideChild - tester.getCenter(finder));
  node.onDrop(insideChild);
  node.onActiveChanged!(false);
  node.onEnd();
  await tester.pumpAndSettle();
  expect(child.elementIds, contains(memo.id));

  final outside = const Offset(1200, 700);
  final restored = tester.widget<ThoughtInteraction>(finder);
  restored.onActiveChanged!(true);
  restored.onMove(outside - tester.getCenter(finder));
  await tester.pump();
  final childBounds = tester.getRect(find.byKey(const ValueKey('box-region-하위 상자')));
  final parentBounds = tester.getRect(find.byKey(const ValueKey('box-region-상위 상자')));
  expect(childBounds.contains(tester.getCenter(finder)), isTrue);
  expect(parentBounds.contains(tester.getCenter(finder)), isTrue);
  restored.onDrop(outside);
  restored.onActiveChanged!(false);
  restored.onEnd();
  await tester.pumpAndSettle();
  expect(child.elementIds, contains(memo.id));
  await tester.pumpWidget(const SizedBox());
 });
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
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(onChanged:(){})));await tester.pumpAndSettle();
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
