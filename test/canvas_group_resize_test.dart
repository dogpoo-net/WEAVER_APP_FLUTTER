import 'package:flutter/material.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main(){
 for(final selectedUpper in [false,true]){
 for(final left in [false,true]){
 testWidgets('group snaps to upper card selected=$selectedUpper left=$left',(tester)async{
 tester.view.physicalSize=const Size(1400,1000);tester.view.devicePixelRatio=1;
 addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();
 final upper=elements.add('위'),driver=elements.add('조절'),distant=elements.add('멀리');
 final layout=pageGraphLayout.blockLayout;
 layout.positions.addAll({upper.id:const Offset(500,500),driver.id:const Offset(500,532),distant.id:const Offset(950,500)});
 layout.sizes[upper.id]=const Offset(300,120);
 layout.sizes[distant.id]=const Offset(270,120);
 layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
 await tester.tap(find.byType(Checkbox));await tester.pump();
 if(selectedUpper){
 await tester.tapAt(tester.getTopLeft(find.byKey(ValueKey('canvas-thought-${upper.id}')))+const Offset(40,16));await tester.pump();
 }
 for(final record in [driver,distant]){
 await tester.tapAt(tester.getCenter(find.byKey(ValueKey('canvas-thought-${record.id}'))));await tester.pump();
 }
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,selectedUpper?'3':'2');
 final interaction=tester.widget<ThoughtInteraction>(find.byKey(ValueKey('canvas-thought-${driver.id}')));
 interaction.onResizeStart!();
 interaction.onResize(const Size(294,120),left?const Offset(-64,0):Offset.zero);
 await tester.pump();
 expect(layout.sizes[driver.id]!.dx,300);
 expect(layout.sizes[distant.id]!.dx,340);
 expect(layout.sizes[upper.id]!.dx,300);
 interaction.onEnd();
 await tester.pumpAndSettle();
 expect(layout.positions[driver.id]!.dx,left?430:500);
 await tester.pumpWidget(const SizedBox());
 });}}
 for(final side in ['right-bottom','left-top']){
 testWidgets('selection mode resizes both cards from $side',(tester)async{
 tester.view.physicalSize=const Size(1400,1000);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();
 final a=elements.add('첫째'),b=elements.add('둘째'),c=elements.add('제외');
 final layout=pageGraphLayout.blockLayout;
 layout.positions.addAll({a.id:const Offset(500,500),b.id:const Offset(850,500),c.id:const Offset(1200,500)});
 layout.sizes[b.id]=const Offset(270,160);
 layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
 await tester.tap(find.byType(Checkbox));await tester.pump();
 await tester.tapAt(tester.getCenter(find.byKey(ValueKey('canvas-thought-${a.id}'))));await tester.pump();
 await tester.tapAt(tester.getCenter(find.byKey(ValueKey('canvas-thought-${b.id}'))));await tester.pump();
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'2');
 final oldA=layout.positions[a.id]!,oldB=layout.positions[b.id]!;
 final handle=find.descendant(of:find.byKey(ValueKey('canvas-thought-${a.id}')),matching:find.byKey(ValueKey('resize-$side')));
 await tester.drag(handle,side=='left-top'?const Offset(-70,-40):const Offset(70,40));await tester.pumpAndSettle();
 final change=layout.sizes[a.id]!-const Offset(230,120);
 expect(change.dx,greaterThan(20));expect(change.dy,greaterThan(5));
 expect(layout.sizes[b.id]!-const Offset(270,160),change);
 expect(layout.sizes[c.id],isNull);
 expect(layout.positions[a.id],side=='left-top'?oldA-change:oldA);
 expect(layout.positions[b.id],side=='left-top'?oldB-change:oldB);
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'2');
 await tester.pumpWidget(const SizedBox());
 });}
 for(final resize in [false,true]){
 testWidgets('memo edit survives neighbor collision and stale layout resize=$resize',(tester)async{
 SharedPreferences.setMockInitialValues({});final storage=WorkspaceStorage(await SharedPreferences.getInstance());
 tester.view.physicalSize=const Size(1400,1000);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();final a=elements.add('작업'),b=elements.add('이웃');
 memoBoxes.addAll([MemoBox('왼쪽',ids:[a.id]),MemoBox('오른쪽',ids:[b.id])]);
 final layout=pageGraphLayout.blockLayout;
 layout.positions.addAll({a.id:const Offset(500,500),b.id:const Offset(850,500)});
 layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,storage:storage,onChanged:(){})));await tester.pumpAndSettle();
 final before=GraphLayout.fromJson(layout.toJson());
 final card=find.byKey(ValueKey('canvas-thought-${a.id}'));
 final target=resize?find.descendant(of:card,matching:find.byKey(const ValueKey('resize-right'))):card;
 final gesture=await tester.startGesture(tester.getCenter(target));
 await gesture.moveBy(const Offset(20,0));await tester.pump();
 await gesture.moveBy(const Offset(60,0));await tester.pump();
 await gesture.moveBy(const Offset(140,0));await tester.pump(const Duration(milliseconds:400));
 layout.copyFrom(before);storage.liveChanges.value++;
 await gesture.up();await tester.pumpAndSettle();
 if(resize){expect(layout.sizes[a.id]!.dx,greaterThan(300));}
 else{expect(layout.positions[a.id]!.dx,greaterThan(before.positions[a.id]!.dx+80));}
 expect(layout.positions[b.id],isNot(before.positions[b.id]));
 await tester.pumpWidget(const SizedBox());
 });}
}
