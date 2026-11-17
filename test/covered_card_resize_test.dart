import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';

void main(){
 testWidgets('visible rear corner resizes without dragging the viewport or front card',(tester)async{
 tester.view.physicalSize=const Size(1400,900);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();
 final a=elements.add('뒤쪽 본문'),b=elements.add('앞쪽 본문');final layout=pageGraphLayout.blockLayout;
 layout.positions.addAll({a.id:const Offset(500,500),b.id:const Offset(500,532)});
 layout.layers.addAll([a.id,b.id]);layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
 final view=tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
 final beforeView=List<double>.of(view.value.storage);
 final rear=find.byKey(ValueKey('canvas-thought-${a.id}'));
 final handle=find.descendant(of:rear,matching:find.byKey(const ValueKey('resize-right-top')));
 await tester.drag(handle,const Offset(90,-50));await tester.pumpAndSettle();
 expect(layout.sizes[a.id]!.dx,greaterThan(230));expect(layout.sizes[a.id]!.dy,greaterThan(120));
 expect(layout.positions[b.id],const Offset(500,532));expect(view.value.storage,beforeView);
 // Auto-fit preserves the opposite border and measures the actual text.
 final interaction=tester.widget<ThoughtInteraction>(rear);final oldBottom=layout.positions[a.id]!.dy+interaction.size.height;
 final bottomWidth=interaction.size.width;
 final top=find.descendant(of:rear,matching:find.byKey(const ValueKey('resize-top')));
 await tester.tap(top);await tester.pump(const Duration(milliseconds:50));await tester.tap(top);await tester.pumpAndSettle();
 expect(layout.sizes[a.id]!.dx,bottomWidth);
 expect(layout.sizes[a.id]!.dy,lessThan(interaction.size.height));
 expect(layout.positions[a.id]!.dy+layout.sizes[a.id]!.dy,closeTo(oldBottom,.01));
 await tester.pumpWidget(const SizedBox());
 });
}
