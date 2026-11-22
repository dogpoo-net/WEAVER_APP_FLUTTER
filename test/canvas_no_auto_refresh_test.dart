import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
void main(){
 for(final blocks in [true]){
  testWidgets('Idle canvas accepts collaborator geometry ($blocks)',(tester)async{
   SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());
   elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();final record=elements.add('드래그한 배치');
   final layout=blocks?pageGraphLayout.blockLayout:pageGraphLayout;layout.positions[record.id]=const Offset(500,400);
   await tester.pumpWidget(MaterialApp(home:ThoughtPage(storage:storage,onChanged:(){})));await tester.pumpAndSettle();
   final before=tester.getTopLeft(find.text('드래그한 배치'));
   layout.positions[record.id]=const Offset(1100,900);storage.liveChanges.value++;elements.refreshVisibility();
   await tester.pump(const Duration(seconds:3));await tester.pumpAndSettle();
   expect(tester.getTopLeft(find.text('드래그한 배치')),isNot(before));
   await tester.tap(find.byTooltip('저장 (Ctrl+S)'));await tester.pumpAndSettle();expect(layout.positions[record.id],const Offset(1100,900));
   expect(storage.editorResources,isEmpty);
   await tester.pumpWidget(const SizedBox());await tester.pump();expect(storage.editorResources,isEmpty);
  });
 }
}
