import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){for(final blocks in [false,true]){testWidgets('Ctrl drag selects without checking selection ($blocks)',(tester)async{
 tester.view.physicalSize=const Size(1200,900);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();final a=elements.add('첫 생각'),b=elements.add('둘째 생각');final layout=blocks?pageGraphLayout.blockLayout:pageGraphLayout;
 layout.positions[a.id]=const Offset(500,500);layout.positions[b.id]=const Offset(800,500);layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){})));await tester.pumpAndSettle();
 final view=tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));final before=List<double>.of(view.transformationController!.value.storage);
 await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);await tester.pump();expect(tester.widget<Checkbox>(find.byType(Checkbox)).value,isFalse);
 final box=tester.renderObject<RenderBox>(find.byKey(const ValueKey('canvas-selection')));final gesture=await tester.startGesture(box.localToGlobal(const Offset(470,470)));
 await gesture.moveTo(box.localToGlobal(const Offset(1060,650)));await tester.pump();await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);await tester.pump();
 expect(find.byKey(const ValueKey('canvas-selection')),findsOneWidget);await gesture.up();await tester.pumpAndSettle();
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'2');expect(view.transformationController!.value.storage,before);
 expect(tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).panEnabled,isTrue);await tester.pumpWidget(const SizedBox());
});}}
