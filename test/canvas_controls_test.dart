import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';

void main() {
  for (final blocks in [false, true]) {
    testWidgets('link guidance overlays the canvas and cards have no drag link control ($blocks)', (tester) async {
      elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout();
      elements.add('넓게 표시할 생각');
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: blocks, onChanged: () {})));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(InteractiveViewer));
      expect(find.descendant(of: find.byType(ThoughtInteraction), matching: find.byIcon(Icons.link)), findsNothing);
      expect(find.byType(Draggable<String>), findsNothing);
      expect(find.byType(DragTarget<String>), findsNothing);
      await tester.tap(find.byTooltip('연결 모드')); await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(InteractiveViewer)), before);
      expect(before.contains(tester.getCenter(find.text('생각 두 개를 차례로 눌러 연결하거나 해제하세요.'))), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
