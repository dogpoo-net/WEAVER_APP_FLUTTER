import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/memo_folder_region.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
void main(){
 for(final kind in ['thought','box','folder']){
 testWidgets('delayed snapshot after $kind drop cannot roll back local geometry',(tester)async{
  SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());
  elements.clear();memoBoxes.clear();memoBoxFolders.clear();memoBoxFolderParents.clear();pageGraphLayout=GraphLayout();
  final record=elements.add('움직인 생각');
  if(kind!='thought')memoBoxes.add(MemoBox('상자',ids:[record.id],folder:kind=='folder'?'폴더':null));
  if(kind=='folder')memoBoxFolders.add('폴더');
  final layout=pageGraphLayout.blockLayout;layout.positions[record.id]=const Offset(600,500);
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,storage:storage,onChanged:(){})));await tester.pumpAndSettle();
  final before=layout.positions[record.id]!;
  if(kind=='thought'){final node=tester.widget<ThoughtInteraction>(find.byKey(ValueKey('canvas-thought-${record.id}')));node.onMove(const Offset(130,70));node.onEnd();}
  if(kind=='box'){final box=tester.widget<MemoBoxRegion>(find.byKey(const ValueKey('box-region-상자')));box.onDrag!(const Offset(130,70));box.onDragEnd!();}
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
