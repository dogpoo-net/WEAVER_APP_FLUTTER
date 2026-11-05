import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('page removes only the selected reciprocal link and persists it', (tester) async {
    elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout();
    final a = elements.add('생각 A #태그');
    final b = elements.add('생각 B'); final c = elements.add('생각 C');
    elements.connect(a.id, [b.id, c.id]);
    String? saved;
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () => saved = WorkspaceSnapshot.encode([]))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('생각 A'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결 끊기')); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('생각 B')));
    await tester.pumpAndSettle();
    expect(a.connections, {c.id}); expect(b.connections, isEmpty); expect(c.connections, {a.id});
    expect(a.tags, {'태그'});
    final restored = WorkspaceSnapshot.decode(saved!);
    expect(restored.records.firstWhere((r) => r.id == b.id).connections, isEmpty);
    await tester.tap(find.text('연결 끊기')); await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('#태그')));
    await tester.pumpAndSettle();
    expect(a.tags, isEmpty); expect(a.connections, {c.id});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
