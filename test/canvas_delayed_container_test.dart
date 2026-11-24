import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_folder_region.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
void main(){
 testWidgets('dragging upward within a stack commits one slot at a time', (tester) async {
   elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); pageGraphLayout = GraphLayout();
   final ids = [for (final title in ['뒤', '가운데', '앞']) elements.add(title).id];
   final layout = pageGraphLayout.blockLayout;
   for (var i = 0; i < ids.length; i++) {
     layout.positions[ids[i]] = Offset(600, 500 + i * 32);
     layout.stackGroups[ids[i]] = 'stack';
   }
   layout.layers.addAll(ids);
   await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
   await tester.pumpAndSettle();
   final finder = find.byKey(ValueKey('canvas-thought-${ids.last}'));
   for (final y in [532.0, 500.0]) {
     final node = tester.widget<ThoughtInteraction>(finder);
     node.onActiveChanged!(true);
     node.onMove(const Offset(0,-32));
     node.onDrop(tester.getCenter(finder) - const Offset(0,32));
     node.onActiveChanged!(false);
     node.onEnd();
     await tester.pumpAndSettle();
     expect(layout.positions[ids.last], Offset(600,y));
     expect(layout.layers.indexOf(ids.last), y == 532 ? 1 : 0);
   }
   await tester.pumpWidget(const SizedBox());
 });
 testWidgets('detached thought can return to its original stack slot', (tester) async {
   SharedPreferences.setMockInitialValues({});
   final storage = WorkspaceStorage(await SharedPreferences.getInstance());
   elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); pageGraphLayout = GraphLayout();
   final back = elements.add('뒤'), front = elements.add('앞');
   final layout = pageGraphLayout.blockLayout;
   const slot = Offset(600,532);
   layout.positions.addAll({back.id: const Offset(600,500), front.id: slot});
   layout.stackGroups.addAll({back.id:'original', front.id:'original'});
   layout.layers.addAll([back.id,front.id]);
   await tester.pumpWidget(MaterialApp(home:ThoughtPage(storage:storage,onChanged:(){})));
   await tester.pumpAndSettle();
   final finder = find.byKey(ValueKey('canvas-thought-${front.id}'));
   Future<void> drag(Offset delta) async {
     final node = tester.widget<ThoughtInteraction>(finder);
     node.onActiveChanged!(true);
     node.onMove(delta);
     node.onDrop(tester.getCenter(finder) + delta);
     node.onActiveChanged!(false);
     node.onEnd();
     await tester.pumpAndSettle();
   }
   await drag(const Offset(350,0));
   expect(layout.stackGroups[front.id], isNot(layout.stackGroups[back.id]));
   await drag(slot - layout.positions[front.id]!);
   expect(layout.positions[front.id], slot);
   expect(layout.stackGroups[front.id], layout.stackGroups[back.id]);
   await tester.pumpWidget(const SizedBox());
 });

 for(final kind in ['thought','box','folder','pointer','pointerBox','pointerFolder']){
 testWidgets('delayed snapshot after $kind drop cannot roll back local geometry',(tester)async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());
  elements.clear();memoBoxes.clear();memoBoxFolders.clear();memoBoxFolderParents.clear();pageGraphLayout=GraphLayout();
  final record=elements.add('움직인 생각');
  if(kind!='thought'&&kind!='pointer')memoBoxes.add(MemoBox('상자',ids:[record.id],folder:(kind=='folder'||kind=='pointerFolder')?'폴더':null));
  if(kind=='folder'||kind=='pointerFolder')memoBoxFolders.add('폴더');
  final layout=pageGraphLayout.blockLayout;layout.positions[record.id]=const Offset(600,500);
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(storage:storage,onChanged:(){})));await tester.pumpAndSettle();
  final before=layout.positions[record.id]!;
  if(kind=='pointer'){await tester.drag(find.byKey(ValueKey('canvas-thought-${record.id}')),const Offset(130,70));}
  if(kind=='pointerBox'){await tester.drag(find.byKey(const ValueKey('box-drag-header-상자')),const Offset(130,70));}
  if(kind=='pointerFolder'){await tester.dragFrom(tester.getTopLeft(find.byKey(const ValueKey('folder-region-폴더')))+const Offset(50,20),const Offset(130,70));}
  if(kind=='thought'){final node=tester.widget<ThoughtInteraction>(find.byKey(ValueKey('canvas-thought-${record.id}')));node.onMove(const Offset(130,70));node.onEnd();}
  if(kind=='box'){
    final header=find.byKey(const ValueKey('box-drag-header-상자'));
    final drag=tester.widget<GestureDetector>(header);
    final start=tester.getCenter(header);
    drag.onScaleStart!(ScaleStartDetails(focalPoint:start));
    drag.onScaleUpdate!(ScaleUpdateDetails(focalPoint:start+const Offset(130,70),pointerCount:1));
    drag.onScaleEnd!(ScaleEndDetails());
  }
  if(kind=='folder'){final folder=tester.widget<MemoFolderRegion>(find.byKey(const ValueKey('folder-region-폴더')));folder.onMove(const Offset(130,70));folder.onEnd();}
  await tester.pumpAndSettle();await tester.pump(const Duration(milliseconds:400));
  final moved=layout.positions[record.id]!;expect((moved-before).distance,greaterThan(30));
  layout.positions[record.id]=before;storage.liveChanges.value++;
  await tester.pumpAndSettle();await tester.pump(const Duration(milliseconds:400));
  expect(layout.positions[record.id],moved);
  // Once our position is observed, a later collaborator move must still apply.
  layout.positions[record.id]=moved;storage.liveChanges.value++;await tester.pumpAndSettle();
  final collaborator=moved+const Offset(40,30);layout.positions[record.id]=collaborator;storage.liveChanges.value++;await tester.pumpAndSettle();
  expect(layout.positions[record.id],collaborator);
  await tester.pumpWidget(const SizedBox());
 });
 }
}
