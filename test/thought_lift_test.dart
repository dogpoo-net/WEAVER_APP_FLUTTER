import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout(); });
  testWidgets('long press lifts a thought out of its box without deleting it', (tester) async {
    final a = elements.add('꺼낼 생각'); final b = elements.add('남길 생각'); final c = elements.add('상자 바깥');
    final box = MemoBox('상자', ids: [a.id, b.id]); memoBoxes.add(box);
    pageGraphLayout.positions.addAll({a.id: const Offset(800, 600), b.id: const Offset(1000, 600), c.id: const Offset(800, 1200)});
    String? saved;
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () => saved = WorkspaceSnapshot.encode([]))));
    await tester.pumpAndSettle();
    final from = tester.getCenter(find.text('꺼낼 생각'));
    final to = tester.getCenter(find.text('상자 바깥'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 650));
    final lifted = find.descendant(of: find.ancestor(of: find.text('꺼낼 생각'), matching: find.byType(ThoughtInteraction)), matching: find.byType(AnimatedScale));
    expect(tester.widget<AnimatedScale>(lifted).scale, greaterThan(1));
    await gesture.moveTo(to); await tester.pump(); await gesture.up(); await tester.pumpAndSettle();
    expect(box.elementIds, {b.id});
    expect(elements.records.containsKey('꺼낼 생각'), isTrue);
    expect(WorkspaceSnapshot.decode(saved!).boxes.single.elementIds, {b.id});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('saved negative coordinates recover together and remain draggable', (tester) async {
    final a = elements.add('왼쪽 생각'); final b = elements.add('다른 생각');
    pageGraphLayout.positions.addAll({a.id: const Offset(-400, -200), b.id: const Offset(100, 100)});
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pageGraphLayout.positions[a.id]!.dx, greaterThanOrEqualTo(32));
    expect(pageGraphLayout.positions[a.id]!.dy, greaterThanOrEqualTo(32));
    expect(pageGraphLayout.positions[b.id]! - pageGraphLayout.positions[a.id]!, const Offset(500, 300));
    final before = pageGraphLayout.positions[a.id]!;
    await tester.drag(find.text('왼쪽 생각'), const Offset(70, 20));
    await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
    expect(pageGraphLayout.positions[a.id]!.dx, greaterThan(before.dx), reason: 'Recovered nodes must receive input, not just paint inside the canvas.');
    await tester.drag(find.text('왼쪽 생각'), const Offset(-1500, -1500));
    await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
    expect(pageGraphLayout.positions[a.id]!.dx, greaterThanOrEqualTo(32));
    expect(pageGraphLayout.positions[a.id]!.dy, greaterThanOrEqualTo(32));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
