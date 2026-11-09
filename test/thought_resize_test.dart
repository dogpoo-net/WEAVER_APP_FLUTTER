import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/graph_layout.dart';

void main() {
  for (final desktop in [true, false]) {
    testWidgets('resize changes the card and preserves font size (desktop=$desktop)', (tester) async {
      var size = const Size(178, 84);
      var drops = 0;
      final view = TransformationController();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InteractiveViewer(
        transformationController: view,
        child: Center(child: StatefulBuilder(builder: (context, update) => ThoughtInteraction(
          size: size, desktop: desktop, onMove: (_) {}, onDrop: (_) => drops++, onEnd: () {},
          onTap: () {}, onResize: (next, shift) => update(() => size = next),
          child: const Text('같은 폰트 크기로 긴 생각의 내용을 계속 표시합니다.', style: TextStyle(fontSize: 14)),
        ))),
      ))));
      if (desktop) {
        await tester.drag(find.byKey(const ValueKey('resize-right-bottom')), const Offset(90, 60));
      } else {
        final center = tester.getCenter(find.byType(ThoughtInteraction));
        // Both fingers start just outside the visible card border.
        final distance = size.width / 2 + 6;
        final a = await tester.startGesture(center - Offset(distance, 0), pointer: 1);
        final b = await tester.startGesture(center + Offset(distance, 0), pointer: 2);
        await tester.pump();
        for (var step = 1; step <= 4; step++) {
          await a.moveTo(center - Offset(distance + step * 12, 0));
          await b.moveTo(center + Offset(distance + step * 12, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await a.up(); await b.up();
      }
      await tester.pumpAndSettle();
      expect(size.width, greaterThan(178));
      expect(size.height, greaterThan(84));
      expect(tester.widget<Text>(find.text('같은 폰트 크기로 긴 생각의 내용을 계속 표시합니다.')).style!.fontSize, 14);
      expect(view.value.getMaxScaleOnAxis(), 1);
      expect(drops, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      view.dispose();
    });
  }
  test('card sizes survive layout serialization and legacy layouts use defaults', () {
    final layout = GraphLayout()..sizes['thought'] = const Offset(320, 240);
    expect(GraphLayout.fromJson(layout.toJson()).sizes['thought'], const Offset(320, 240));
    expect(GraphLayout.fromJson({}).sizes, isEmpty);
  });
}
