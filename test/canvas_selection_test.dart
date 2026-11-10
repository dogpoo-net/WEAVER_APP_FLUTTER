import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  for (final blocks in [false, true]) {
    testWidgets('range selection moves thoughts together without panning ($blocks)', (tester) async {
      elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout();
      tester.view.physicalSize = const Size(1200, 900); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final a = elements.add('첫 생각'), b = elements.add('둘째 생각');
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      layout.positions[a.id] = const Offset(500, 500);
      layout.positions[b.id] = const Offset(800, 500);
      layout.viewport = (Matrix4.identity()..setTranslationRaw(-400, -400, 0)).storage.toList();
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: blocks, onChanged: () {})));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final transform = List<double>.of(viewer.transformationController!.value.storage);
      await tester.tap(find.text('선택')); await tester.pumpAndSettle();
      final overlay = tester.renderObject<RenderBox>(find.byKey(const ValueKey('canvas-selection')));
      final gesture = await tester.startGesture(overlay.localToGlobal(const Offset(470, 470)));
      await gesture.moveTo(overlay.localToGlobal(const Offset(1060, 650))); await tester.pump();
      await gesture.up(); await tester.pumpAndSettle();
      expect(find.text('선택 2'), findsOneWidget);
      final move = await tester.startGesture(overlay.localToGlobal(const Offset(550, 540)));
      await move.moveBy(const Offset(30, 20)); await tester.pump();
      await move.moveBy(const Offset(40, 30)); await tester.pump();
      await move.up(); await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
      expect(layout.positions[a.id]!.dx, greaterThan(500));
      expect(layout.positions[b.id]! - layout.positions[a.id]!, const Offset(300, 0));
      expect(viewer.transformationController!.value.storage, transform);
      await tester.tapAt(overlay.localToGlobal(const Offset(1100, 800))); await tester.pump();
      expect(find.text('선택'), findsOneWidget);
      final otherBefore = layout.positions[b.id];
      final single = await tester.startGesture(overlay.localToGlobal(layout.positions[a.id]! + const Offset(40, 40)));
      await single.moveBy(const Offset(30, 20)); await tester.pump();
      await single.moveBy(const Offset(40, 20)); await tester.pump();
      await single.up(); await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('선택 1'), findsOneWidget);
      expect(layout.positions[b.id], otherBefore);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
