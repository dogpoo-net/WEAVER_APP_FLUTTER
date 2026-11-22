import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_geometry.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){
 for(final blocks in [true]){
  testWidgets('canvas boundary remains mounted and follows zoom (blocks=$blocks)',(tester)async{
   elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();elements.add('경계 확인');
   await tester.pumpWidget(MaterialApp(home:ThoughtPage(onChanged:(){})));await tester.pumpAndSettle();
   final boundary=find.byKey(const ValueKey('canvas-boundary'));expect(boundary,findsOneWidget);
   final view=tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
   for(final scale in [.15,1.0,4.0]){
    view.value=Matrix4.diagonal3Values(scale,scale,scale);await tester.pump();
    expect((tester.widget<CustomPaint>(boundary).painter as CanvasBoundaryPainter).scale,closeTo(scale,.001));
   }
   await tester.pumpWidget(const SizedBox());
  });
 }
}
